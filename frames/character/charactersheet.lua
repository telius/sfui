local addonName, addon = ...
sfui = sfui or {}
sfui.character = sfui.character or {}
sfui.character.sheet = {}

-- guard: retail only
if not sfui.isRetail then
    return
end

-- ══════════════════════════════════════════════════════════════════════════════
-- sfui/frames/character/charactersheet.lua
-- streamlined hybrid character sheet (chonky layout + ellesmere lean efficiency)
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local hooksecurefunc = _G.hooksecurefunc
local InCombatLockdown = _G.InCombatLockdown
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetInventoryItemDurability = _G.GetInventoryItemDurability
local GetInventoryItemID = _G.GetInventoryItemID
local GetAverageItemLevel = _G.GetAverageItemLevel
local UnitLevel = _G.UnitLevel
local UnitName = _G.UnitName
local UnitPVPName = _G.UnitPVPName
local UnitClass = _G.UnitClass
local UnitStat = _G.UnitStat
local UnitArmor = _G.UnitArmor
local UnitHealthMax = _G.UnitHealthMax
local UnitSpellHaste = _G.UnitSpellHaste
local UnitAttackPower = _G.UnitAttackPower
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitHonorLevel = _G.UnitHonorLevel
local UnitHonor = _G.UnitHonor
local UnitHonorMax = _G.UnitHonorMax
local GetCombatRating = _G.GetCombatRating
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local GetVersatilityBonus = _G.GetVersatilityBonus
local GetMasteryEffect = _G.GetMasteryEffect
local GetCritChance = _G.GetCritChance
local GetHaste = _G.GetHaste
local GetLifesteal = _G.GetLifesteal
local GetAvoidance = _G.GetAvoidance
local GetSpeed = _G.GetSpeed
local GetDodgeChance = _G.GetDodgeChance
local GetParryChance = _G.GetParryChance
local GetBlockChance = _G.GetBlockChance
local GetSpellBonusDamage = _G.GetSpellBonusDamage
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo
local GetNumSpecializations = _G.GetNumSpecializations
local SetSpecialization = _G.SetSpecialization
local GetLootSpecialization = _G.GetLootSpecialization
local SetLootSpecialization = _G.SetLootSpecialization
local GetUnitSpeed = _G.GetUnitSpeed
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers or tostring
local tostring = _G.tostring
local tonumber = _G.tonumber
local pairs = _G.pairs
local ipairs = _G.ipairs
local math_floor = math.floor
local math_max = math.max
local string_format = string.format
local CreateColor = _G.CreateColor

local C_Item = _G.C_Item
local C_TooltipInfo = _G.C_TooltipInfo
local C_CurrencyInfo = _G.C_CurrencyInfo
local C_ChallengeMode = _G.C_ChallengeMode
local TooltipUtil = _G.TooltipUtil
local ItemLocation = _G.ItemLocation

local common = sfui.common
local issecretvalue = (common and common.issecretvalue) or _G.issecretvalue or function() return false end
local GameTooltip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip

local PANEL_WIDTH = 708
local PANEL_HEIGHT = 512

-- weak-keyed lookup table to avoid tainting blizzard objects
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    if not frame then return {} end
    local d = FFD[frame]
    if not d then
        d = {}
        FFD[frame] = d
    end
    return d
end

local sheetFrame
local function EnsureSheetFrame()
    if sheetFrame then return sheetFrame end
    sheetFrame = _G.SfuiCharacterSheetFrame
    if not sheetFrame then
        sheetFrame = CreateFrame("Frame", "SfuiCharacterSheetFrame", CharacterFrame, "BackdropTemplate")
        sheetFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        sheetFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
        sheetFrame:SetFrameStrata("LOW")
        sheetFrame:SetFrameLevel(1)
    end
    if BackdropTemplateMixin and not sheetFrame.SetBackdrop then
        Mixin(sheetFrame, BackdropTemplateMixin)
    end
    if not sheetFrame.sfuiSolidBg then
        local bg = sheetFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints(sheetFrame)
        sheetFrame.sfuiSolidBg = bg
    end
    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    if pal and pal.backdropColor and sheetFrame.sfuiSolidBg then
        local c = pal.backdropColor
        sheetFrame.sfuiSolidBg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.95)
        sheetFrame.sfuiSolidBg:Show()
    end
    sheetFrame:Show()
    return sheetFrame
end


local function GetFont()
    return (common and common.get_font_file and common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
end

local function StripFont(fs, size)
    if not fs then return end
    fs:SetFont(GetFont(), size or 10, "")
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- upgrade track mapping (all lowercase)
-- ─────────────────────────────────────────────────────────────────────────────
local TRACK_COLORS = {
    myth       = "ffff8000",
    hero       = "ffa335ee",
    champion   = "ff0070dd",
    veteran    = "ff1eff00",
    adventurer = "ffffffff",
    explorer   = "ff9d9d9d",
}

local function ParseUpgradeTrack(itemLink)
    if not itemLink or not C_Item or not C_Item.GetItemUpgradeInfo then return nil end
    local info = C_Item.GetItemUpgradeInfo(itemLink)
    if not info or not info.trackString or info.trackString == "" then return nil end
    local track = info.trackString:lower()
    local cur = info.currentLevel or 0
    local maxL = info.maxLevel or 0
    if maxL > 0 and cur > maxL then
        cur = maxL
    end
    local colorHex = TRACK_COLORS[track] or "ffffffff"
    if cur > 0 and maxL > 0 then
        return string_format("|c%s(%s %d/%d)|r", colorHex, track, cur, maxL)
    end
    return string_format("|c%s(%s)|r", colorHex, track)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- tooltip scanning for enchant line (clean, lowercase, language-agnostic)
-- ─────────────────────────────────────────────────────────────────────────────
local _enchantCache = {}
local _ENCHANT_LINE_TYPE = (Enum and Enum.TooltipDataLineType
    and (Enum.TooltipDataLineType.ItemEnchantmentPermanent or Enum.TooltipDataLineType.ItemEnchant)) or 15

local ENCHANT_ELIGIBLE_SLOTS = {
    [1]  = false, -- head (situational/helm enchants in older expansions)
    [2]  = false, -- neck
    [3]  = false, -- shoulder
    [5]  = true,  -- chest
    [6]  = false, -- waist
    [7]  = true,  -- legs
    [8]  = true,  -- feet
    [9]  = true,  -- wrist
    [10] = false, -- hands
    [11] = true,  -- ring 1
    [12] = true,  -- ring 2
    [15] = true,  -- cloak
    [16] = true,  -- main hand
    [17] = true,  -- off hand
}

local function GetSlotEnchant(slotID, itemLink)
    if not slotID or not itemLink then return "", false end
    local enchantID = tonumber(itemLink:match("item:%d+:(%d+)"))
    local enchantName = ""

    if enchantID and enchantID > 0 then
        if _enchantCache[enchantID] then
            enchantName = _enchantCache[enchantID]
        elseif C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
            local data = C_TooltipInfo.GetInventoryItem("player", slotID)
            if data then
                if TooltipUtil and TooltipUtil.SurfaceArgs then
                    TooltipUtil.SurfaceArgs(data)
                end
                if data.lines then
                    for _, line in ipairs(data.lines) do
                        if line.type == _ENCHANT_LINE_TYPE then
                            local text = line.leftText or ""
                            text = text:gsub("|A:.-|a", ""):gsub("|T.-|t", "")
                            text = text:gsub("|cn.-:(.-)|r", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                            text = text:gsub("^[Ee]nchanted:%s*", ""):gsub("^[Ee]nchant%s+[^-]+%s*-%s*", "")
                            text = text:gsub("^%s+", ""):gsub("%s+$", "")
                            if text ~= "" then
                                enchantName = text:lower()
                                _enchantCache[enchantID] = enchantName
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    local isEligible = ENCHANT_ELIGIBLE_SLOTS[slotID] == true
    local lvl = UnitLevel("player")
    local atMaxLevel = lvl and not issecretvalue(lvl) and lvl >= 70
    local isMissing = isEligible and atMaxLevel and (enchantName == "")
    return enchantName, isMissing
end

-- ─────────────────────────────────────────────────────────────────────────────
-- gem sockets parsing
-- ─────────────────────────────────────────────────────────────────────────────
local EMPTY_SOCKET_ATLASES = {
    EMPTY_SOCKET_PRISMATIC  = true,
    EMPTY_SOCKET_PUNCHCARDRED = true,
    EMPTY_SOCKET_PUNCHCARDYELLOW = true,
    EMPTY_SOCKET_PUNCHCARDBLUE = true,
    EMPTY_SOCKET_DOMINATION = true,
    EMPTY_SOCKET_CYPHER     = true,
    EMPTY_SOCKET_TINKER     = true,
}

local function GetSlotSockets(itemLink)
    local sockets = {}
    if not itemLink or not C_Item or not C_Item.GetItemStats then
        return sockets
    end

    local stats = C_Item.GetItemStats(itemLink)
    local totalSockets = 0
    if stats then
        for k, count in pairs(stats) do
            if EMPTY_SOCKET_ATLASES[k] and count and count > 0 then
                totalSockets = totalSockets + count
            end
        end
    end

    for i = 1, 4 do
        local _, gemLink = C_Item.GetItemGem(itemLink, i)
        if gemLink then
            local icon = C_Item.GetItemIconByID(gemLink)
            if not icon then
                icon = select(5, C_Item.GetItemInfoInstant(gemLink))
            end
            sockets[#sockets + 1] = {
                filled  = true,
                icon    = icon or 134400,
                gemLink = gemLink,
            }
        end
    end

    local emptyNeeded = math_max(0, totalSockets - #sockets)
    for _ = 1, emptyNeeded do
        sockets[#sockets + 1] = {
            filled = false,
            icon   = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic",
        }
    end

    return sockets
end

-- ─────────────────────────────────────────────────────────────────────────────
-- set item detection (tier sets / item sets)
-- ─────────────────────────────────────────────────────────────────────────────
local _setItemCache = {}
local function IsSetItem(slotID, itemLink)
    if not itemLink then return false end
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if itemID and _setItemCache[itemID] ~= nil then
        return _setItemCache[itemID]
    end

    -- 1. native C_Item.GetItemInfo (16th return is setID)
    local setID = select(16, C_Item.GetItemInfo(itemLink))
    if setID and not issecretvalue(setID) and setID > 0 then
        if itemID then _setItemCache[itemID] = true end
        return true
    end

    -- 2. tooltip data scan fallback
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem and slotID then
        local data = C_TooltipInfo.GetInventoryItem("player", slotID)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if text and type(text) == "string" and not issecretvalue(text) then
                    if text:find("%(%d+/%d+%)") or text:find("^[Ss]et:") or text:find("%(%d+%)%s*[Ss]et") then
                        if itemID then _setItemCache[itemID] = true end
                        return true
                    end
                end
            end
        end
    end

    if itemID and setID ~= nil then
        _setItemCache[itemID] = false
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- durability & repair cost formatting
-- ─────────────────────────────────────────────────────────────────────────────
local function GetTotalDurabilityAndRepairCost()
    local lowest = 100
    local totalCost = 0

    for slot = 1, 18 do
        local cur, maxD = GetInventoryItemDurability(slot)
        if cur and maxD and not issecretvalue(cur) and not issecretvalue(maxD) and maxD > 0 then
            local pct = (cur / maxD) * 100
            if pct < lowest then
                lowest = pct
            end
        end

        if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
            local tip = C_TooltipInfo.GetInventoryItem("player", slot)
            if tip and tip.repairCost and not issecretvalue(tip.repairCost) then
                totalCost = totalCost + tip.repairCost
            end
        end
    end

    return math_floor(lowest), totalCost
end

local function FormatMoneyCompact(cost)
    if not cost or cost <= 0 then return "" end
    local gold   = math_floor(cost / 10000)
    local silver = math_floor((cost % 10000) / 100)
    local copper = cost % 100

    local out = ""
    if gold > 0 then
        out = out .. string_format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t ", BreakUpLargeNumbers(gold))
    end
    if silver > 0 or gold > 0 then
        out = out .. string_format("|cffffffff%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t ", silver)
    end
    out = out .. string_format("|cffeda55f%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t", copper)
    return out
end

-- ─────────────────────────────────────────────────────────────────────────────
-- equipment slot definitions
-- ─────────────────────────────────────────────────────────────────────────────
local EQUIPMENT_SLOTS = {
    -- left column
    { id = 1,  name = "CharacterHeadSlot",          side = "left" },
    { id = 2,  name = "CharacterNeckSlot",          side = "left" },
    { id = 3,  name = "CharacterShoulderSlot",      side = "left" },
    { id = 15, name = "CharacterBackSlot",          side = "left" },
    { id = 5,  name = "CharacterChestSlot",         side = "left" },
    { id = 4,  name = "CharacterShirtSlot",         side = "left" },
    { id = 19, name = "CharacterTabardSlot",        side = "left" },
    { id = 9,  name = "CharacterWristSlot",         side = "left" },

    -- right column
    { id = 10, name = "CharacterHandsSlot",         side = "right" },
    { id = 6,  name = "CharacterWaistSlot",         side = "right" },
    { id = 7,  name = "CharacterLegsSlot",          side = "right" },
    { id = 8,  name = "CharacterFeetSlot",          side = "right" },
    { id = 11, name = "CharacterFinger0Slot",       side = "right" },
    { id = 12, name = "CharacterFinger1Slot",       side = "right" },
    { id = 13, name = "CharacterTrinket0Slot",      side = "right" },
    { id = 14, name = "CharacterTrinket1Slot",      side = "right" },

    -- weapons
    { id = 16, name = "CharacterMainHandSlot",      side = "bottom_left" },
    { id = 17, name = "CharacterSecondaryHandSlot", side = "bottom_right" },
}

-- ─────────────────────────────────────────────────────────────────────────────
-- slot button skinning & widgets
-- ─────────────────────────────────────────────────────────────────────────────
local function SkinSlotButton(slotButton)
    if not slotButton then return end

    -- strip default normal texture
    local normal = slotButton.NormalTexture or (slotButton.GetNormalTexture and slotButton:GetNormalTexture())
    if normal then
        normal:SetTexture(nil)
        normal:Hide()
        normal:SetAlpha(0)
    end

    -- suppress blizzard quality frame (replaced by clean 1px square border)
    if slotButton.IconBorder then
        slotButton.IconBorder:SetAlpha(0)
        slotButton.IconBorder:Hide()
        if not slotButton.IconBorder.sfuiHooked then
            slotButton.IconBorder.sfuiHooked = true
            hooksecurefunc(slotButton.IconBorder, "Show", function(self) self:Hide() end)
            hooksecurefunc(slotButton.IconBorder, "SetShown", function(self, shown) if shown then self:Hide() end end)
        end
    end

    -- suppress blizzard overlay textures
    if slotButton.IconOverlay then slotButton.IconOverlay:SetAlpha(0); slotButton.IconOverlay:Hide() end
    if slotButton.IconOverlay2 then slotButton.IconOverlay2:SetAlpha(0); slotButton.IconOverlay2:Hide() end
    if slotButton.SocketDisplay then
        slotButton.SocketDisplay:Hide()
        if not slotButton.SocketDisplay.sfuiHooked then
            slotButton.SocketDisplay.sfuiHooked = true
            slotButton.SocketDisplay:HookScript("OnShow", function(self) self:Hide() end)
        end
    end

    -- clean hover highlight & pushed textures
    local hl = slotButton.HighlightTexture or (slotButton.GetHighlightTexture and slotButton:GetHighlightTexture())
    if hl then
        hl:SetColorTexture(1, 1, 1, 0.18)
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -1, 1)
        hl:SetBlendMode("ADD")
    end

    local push = slotButton.PushedTexture or (slotButton.GetPushedTexture and slotButton:GetPushedTexture())
    if push then
        push:SetColorTexture(1, 1, 1, 0.25)
        push:ClearAllPoints()
        push:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 1, -1)
        push:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -1, 1)
    end

    -- cooldown frame
    local cd = slotButton.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 1, -1)
        cd:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -1, 1)
    end

    -- stack count text
    if slotButton.Count then
        StripFont(slotButton.Count, 10)
    end

    -- dark backing texture behind icon
    if not slotButton.sfuiSlotBg then
        local sbg = slotButton:CreateTexture(nil, "BACKGROUND", nil, -8)
        sbg:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
        sbg:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
        sbg:SetColorTexture(0.04, 0.04, 0.06, 0.95)
        slotButton.sfuiSlotBg = sbg
    end

    -- 1px clean square border lines
    if not slotButton.borders then
        common.create_border(slotButton, 1, { 0.12, 0.12, 0.15, 0.95 })
        if slotButton.borders then
            for _, b in ipairs(slotButton.borders) do
                b:SetDrawLayer("OVERLAY", 6)
            end
        end
    end

    -- zoom and crop icon to standard square (0.08..0.92) using core helper
    local icon = slotButton.icon or _G[slotButton:GetName() .. "IconTexture"]
    if icon then
        common.apply_square_icon_style(slotButton, icon)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -1, 1)

        if not icon.sfuiHooked then
            icon.sfuiHooked = true
            hooksecurefunc(icon, "SetTexCoord", function(self, left, right, top, bottom)
                if self._sfuiEnforcing then return end
                if (not left) or (left == 0 and right == 1 and top == 0 and bottom == 1) then
                    self._sfuiEnforcing = true
                    common.apply_square_icon_style(slotButton, self)
                    self:ClearAllPoints()
                    self:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 1, -1)
                    self:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -1, 1)
                    self._sfuiEnforcing = false
                end
            end)
        end

        if common.sync_masque then
            common.sync_masque(slotButton, { Icon = icon })
        end
    end
end

local function SetSlotBorderColor(slotButton, r, g, b, a)
    if not slotButton then return end
    common.create_border(slotButton, 1, r, g, b, a or 1)
    if slotButton.borders then
        for _, border in ipairs(slotButton.borders) do
            border:SetDrawLayer("OVERLAY", 6)
        end
    end
end

local function EnsureSlotWidgets(slotButton, slotDef)
    local ffd = GetFFD(slotButton)
    if ffd.overlay then return ffd end

    local fontPath = GetFont()
    local side = slotDef.side

    local overlay = CreateFrame("Frame", nil, slotButton)
    overlay:SetAllPoints(slotButton)
    overlay:SetFrameLevel(slotButton:GetFrameLevel() + 5)
    ffd.overlay = overlay

    -- fading colored bar textures
    local barWidth = 145
    local barHeight = 37

    -- subtle dark backing to ensure high text contrast over 3D model scene
    local barBg = overlay:CreateTexture(nil, "BACKGROUND", nil, -2)
    barBg:SetSize(barWidth, barHeight)
    barBg:Hide()
    ffd.barBg = barBg

    -- item quality color gradient bar
    local barGrad = overlay:CreateTexture(nil, "BACKGROUND", nil, -1)
    barGrad:SetSize(barWidth, barHeight)
    barGrad:Hide()
    ffd.barGrad = barGrad

    -- line 1: item name
    local nameText = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
    StripFont(nameText, 10)
    nameText:SetWordWrap(false)
    nameText:SetWidth(138)

    -- line 2: item level & track
    local ilvlText = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
    StripFont(ilvlText, 10)

    -- line 3: enchant text
    local enchantText = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
    StripFont(enchantText, 9)
    enchantText:SetWordWrap(false)
    enchantText:SetWidth(138)

    -- gem icons (up to 3) styled with sfui square borders
    local gemFrames = {}
    for i = 1, 3 do
        local g = CreateFrame("Frame", nil, overlay)
        g:SetSize(12, 12)
        g:SetFrameLevel(overlay:GetFrameLevel() + 3)

        common.create_border(g, 1, { 0, 0, 0, 1 })

        local icon = g:CreateTexture(nil, "ARTWORK")
        common.apply_square_icon_style(g, icon)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", g, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -1, 1)
        g.icon = icon

        g:Hide()
        gemFrames[i] = g
    end

    if side == "left" then
        barBg:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", 0, 0)
        barBg:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMRIGHT", 0, 0)
        barGrad:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", 0, 0)
        barGrad:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMRIGHT", 0, 0)

        nameText:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", 6, -1)
        nameText:SetJustifyH("LEFT")
        ilvlText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        ilvlText:SetJustifyH("LEFT")
        enchantText:SetPoint("TOPLEFT", ilvlText, "BOTTOMLEFT", 0, -2)
        enchantText:SetJustifyH("LEFT")

        -- side gem indicators on the outer left edge of the button
        for i = 1, 3 do
            gemFrames[i]:SetPoint("RIGHT", slotButton, "LEFT", -3 - ((i - 1) * 14), 0)
        end
    elseif side == "right" then
        barBg:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", 0, 0)
        barBg:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMLEFT", 0, 0)
        barGrad:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", 0, 0)
        barGrad:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMLEFT", 0, 0)

        nameText:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", -6, -1)
        nameText:SetJustifyH("RIGHT")
        ilvlText:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -2)
        ilvlText:SetJustifyH("RIGHT")
        enchantText:SetPoint("TOPRIGHT", ilvlText, "BOTTOMRIGHT", 0, -2)
        enchantText:SetJustifyH("RIGHT")

        -- side gem indicators on the outer right edge of the button
        for i = 1, 3 do
            gemFrames[i]:SetPoint("LEFT", slotButton, "RIGHT", 3 + ((i - 1) * 14), 0)
        end
    elseif side == "bottom_left" then
        -- main hand: bar extends to the left
        barBg:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", 0, 0)
        barBg:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMLEFT", 0, 0)
        barBg:SetWidth(105)
        barGrad:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", 0, 0)
        barGrad:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMLEFT", 0, 0)
        barGrad:SetWidth(105)

        nameText:SetPoint("TOPRIGHT", slotButton, "TOPLEFT", -6, -1)
        nameText:SetJustifyH("RIGHT")
        nameText:SetWidth(98)
        ilvlText:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, -2)
        ilvlText:SetJustifyH("RIGHT")
        enchantText:SetPoint("TOPRIGHT", ilvlText, "BOTTOMRIGHT", 0, -2)
        enchantText:SetJustifyH("RIGHT")
        enchantText:SetWidth(98)

        for i = 1, 3 do
            gemFrames[i]:SetPoint("BOTTOM", slotButton, "TOP", -14 + ((i - 1) * 14), 4)
        end
    elseif side == "bottom_right" then
        -- off hand: bar extends to the right
        barBg:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", 0, 0)
        barBg:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMRIGHT", 0, 0)
        barBg:SetWidth(105)
        barGrad:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", 0, 0)
        barGrad:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMRIGHT", 0, 0)
        barGrad:SetWidth(105)

        nameText:SetPoint("TOPLEFT", slotButton, "TOPRIGHT", 6, -1)
        nameText:SetJustifyH("LEFT")
        nameText:SetWidth(98)
        ilvlText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        ilvlText:SetJustifyH("LEFT")
        enchantText:SetPoint("TOPLEFT", ilvlText, "BOTTOMLEFT", 0, -2)
        enchantText:SetJustifyH("LEFT")
        enchantText:SetWidth(98)

        for i = 1, 3 do
            gemFrames[i]:SetPoint("BOTTOM", slotButton, "TOP", -14 + ((i - 1) * 14), 4)
        end
    end

    ffd.nameText = nameText
    ffd.ilvlText = ilvlText
    ffd.enchantText = enchantText
    ffd.gemFrames = gemFrames

    return ffd
end

local function UpdateSlot(slotDef)
    local slotButton = _G[slotDef.name]
    if not slotButton then return end

    local slotFrame = _G[slotDef.name .. "Frame"]
    if slotFrame then slotFrame:Hide() end

    SkinSlotButton(slotButton)

    local ffd = EnsureSlotWidgets(slotButton, slotDef)
    local itemLink = GetInventoryItemLink("player", slotDef.id)
    local icon = slotButton.icon or _G[slotDef.name .. "IconTexture"]

    if not itemLink then
        ffd.nameText:SetText("")
        ffd.ilvlText:SetText("")
        ffd.enchantText:SetText("")
        if ffd.barBg then ffd.barBg:Hide() end
        if ffd.barGrad then ffd.barGrad:Hide() end
        for _, g in ipairs(ffd.gemFrames) do g:Hide() end

        -- empty slot appearance
        SetSlotBorderColor(slotButton, 0.12, 0.12, 0.15, 0.95)
        if icon then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetAlpha(0.35)
            icon:SetDesaturated(true)
        end
        return
    end

    if icon then
        icon:SetAlpha(1.0)
        icon:SetDesaturated(false)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- item name & quality
    local itemName, _, itemQuality = C_Item.GetItemInfo(itemLink)
    local quality = itemQuality or GetInventoryItemQuality("player", slotDef.id)
    local r, g, b = 1, 1, 1
    if quality and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(quality)
    elseif quality and BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[quality] then
        local c = BAG_ITEM_QUALITY_COLORS[quality]
        r, g, b = c.r, c.g, c.b
    end
    ffd.nameText:SetTextColor(r, g, b, 1)
    ffd.nameText:SetText(itemName and itemName:lower() or "")

    -- dynamic 1px quality border around the slot
    SetSlotBorderColor(slotButton, r, g, b, 1)

    -- detect tier/equipment set items
    local isSet = IsSetItem(slotDef.id, itemLink)

    -- dynamic fading rarity bar (lightgold/white for set items, quality color for others)
    if ffd.barBg and ffd.barGrad then
        ffd.barBg:Show()
        ffd.barGrad:Show()
        ffd.barBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        ffd.barGrad:SetTexture("Interface\\Buttons\\WHITE8x8")
        if slotDef.side == "left" or slotDef.side == "bottom_right" then
            ffd.barBg:SetGradient("HORIZONTAL", CreateColor(0.01, 0.01, 0.02, 0.70), CreateColor(0.01, 0.01, 0.02, 0.0))
            if isSet then
                ffd.barGrad:SetGradient("HORIZONTAL", CreateColor(1.0, 0.95, 0.82, 0.55), CreateColor(0.92, 0.82, 0.56, 0.0))
            else
                ffd.barGrad:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.45), CreateColor(r, g, b, 0.0))
            end
        else
            ffd.barBg:SetGradient("HORIZONTAL", CreateColor(0.01, 0.01, 0.02, 0.0), CreateColor(0.01, 0.01, 0.02, 0.70))
            if isSet then
                ffd.barGrad:SetGradient("HORIZONTAL", CreateColor(0.92, 0.82, 0.56, 0.0), CreateColor(1.0, 0.95, 0.82, 0.55))
            else
                ffd.barGrad:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.0), CreateColor(r, g, b, 0.45))
            end
        end
    end

    -- exact item level
    local ilvl = 0
    if ItemLocation then
        local loc = ItemLocation:CreateFromEquipmentSlot(slotDef.id)
        if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
            ilvl = C_Item.GetCurrentItemLevel(loc) or 0
        end
    end
    if ilvl == 0 then
        ilvl = C_Item.GetDetailedItemLevelInfo(itemLink) or 0
    end

    local trackText = ParseUpgradeTrack(itemLink)
    if trackText then
        if slotDef.side == "left" or slotDef.side == "bottom_right" then
            ffd.ilvlText:SetText(string_format("|cffffffff%d|r  %s", ilvl, trackText))
        else
            ffd.ilvlText:SetText(string_format("%s  |cffffffff%d|r", trackText, ilvl))
        end
    else
        ffd.ilvlText:SetText(string_format("|cffffffff%d|r", ilvl))
    end

    -- enchant & missing alert
    local enchantName, isMissing = GetSlotEnchant(slotDef.id, itemLink)
    if enchantName ~= "" then
        ffd.enchantText:SetTextColor(0, 1, 0, 1)
        ffd.enchantText:SetText(enchantName)
    elseif isMissing then
        ffd.enchantText:SetTextColor(1, 0.2, 0.2, 1)
        ffd.enchantText:SetText("missing enchant")
    else
        ffd.enchantText:SetText("")
    end

    -- gem sockets
    local sockets = GetSlotSockets(itemLink)
    for i = 1, 3 do
        local frame = ffd.gemFrames[i]
        local sock = sockets[i]
        if sock then
            frame.icon:SetTexture(sock.icon)
            frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            frame:Show()
        else
            frame:Hide()
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- stats panel
-- ─────────────────────────────────────────────────────────────────────────────
local statsRows = {}

local function CreateCategoryHeader(parent, text, yOffset, r, g, b)
    r = r or 0.20
    g = g or 0.85
    b = b or 0.70

    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(156, 16)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yOffset)

    local label = header:CreateFontString(nil, "OVERLAY")
    StripFont(label, 10)
    label:SetPoint("LEFT", header, "LEFT", 2, 0)
    label:SetTextColor(r, g, b, 1)
    label:SetText(text:lower())

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 6, 0)
    line:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    line:SetColorTexture(r, g, b, 0.4)

    return yOffset - 17
end

local function CreateStatRow(parent, key, labelText, yOffset, tooltipFunc)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(156, 15)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, yOffset)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0)
    row.bg = bg

    local label = row:CreateFontString(nil, "OVERLAY")
    StripFont(label, 9)
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetTextColor(0.68, 0.68, 0.72, 1)
    label:SetText(labelText:lower())

    local value = row:CreateFontString(nil, "OVERLAY")
    StripFont(value, 9)
    value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    value:SetJustifyH("RIGHT")
    value:SetTextColor(1, 1, 1, 1)

    row.label = label
    row.value = value
    row.key = key

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        row.bg:SetColorTexture(1, 1, 1, 0.08)
        if tooltipFunc then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            tooltipFunc(GameTooltip)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        row.bg:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)

    statsRows[key] = row
    return yOffset - 15
end

local function BuildStatsPanel(parent)
    local ffd = GetFFD(parent)
    if ffd.statsPanel then return ffd.statsPanel end

    local canvas = EnsureSheetFrame()
    local panel = CreateFrame("Frame", "SfuiCharacterStatsPanel", parent)
    panel:SetSize(168, 466)
    panel:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -8, -34)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    ffd.statsPanel = panel

    -- background card
    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.025, 0.025, 0.035, 0.85)

    local border = panel:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", panel, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.12, 0.12, 0.16, 0.9)

    -- large item level header (Ellesmere aesthetic)
    local ilvlHeader = panel:CreateFontString(nil, "OVERLAY")
    StripFont(ilvlHeader, 20)
    ilvlHeader:SetPoint("TOP", panel, "TOP", 0, -6)
    ilvlHeader:SetTextColor(0.66, 0.35, 1.0, 1)
    ffd.statsIlvlHeader = ilvlHeader

    local mplusSubtitle = panel:CreateFontString(nil, "OVERLAY")
    StripFont(mplusSubtitle, 10)
    mplusSubtitle:SetPoint("TOP", ilvlHeader, "BOTTOM", 0, -2)
    mplusSubtitle:SetTextColor(0.2, 0.80, 1.0, 1)
    ffd.statsMplusSubtitle = mplusSubtitle

    local y = -46

    -- 1. attributes
    y = CreateCategoryHeader(panel, "attributes", y, 0.20, 0.85, 0.70)
    y = CreateStatRow(panel, "primary", "primary stat", y)
    y = CreateStatRow(panel, "stamina", "stamina", y)
    y = CreateStatRow(panel, "health", "health", y)

    y = y - 4

    -- 2. secondary
    y = CreateCategoryHeader(panel, "secondary", y, 0.40, 0.70, 1.0)
    y = CreateStatRow(panel, "crit", "crit", y, function(tt)
        tt:SetText("critical strike", 1, 1, 1)
        tt:AddLine("chance for attacks and spells to deal additional damage or healing.", 0.8, 0.8, 0.8, true)
    end)
    y = CreateStatRow(panel, "haste", "haste", y, function(tt)
        tt:SetText("haste", 1, 1, 1)
        tt:AddLine("increases attack speed and spell casting speed.", 0.8, 0.8, 0.8, true)
    end)
    y = CreateStatRow(panel, "mastery", "mastery", y, function(tt)
        tt:SetText("mastery", 1, 1, 1)
        tt:AddLine("provides a passive bonus tailored to your class specialization.", 0.8, 0.8, 0.8, true)
    end)
    y = CreateStatRow(panel, "versatility", "versatility", y, function(tt)
        tt:SetText("versatility", 1, 1, 1)
        tt:AddLine("increases damage and healing dealt, and reduces damage taken.", 0.8, 0.8, 0.8, true)
    end)

    y = y - 4

    -- 3. attack
    y = CreateCategoryHeader(panel, "attack", y, 1.0, 0.60, 0.30)
    y = CreateStatRow(panel, "ap", "attack power", y)
    y = CreateStatRow(panel, "speed", "attack speed", y)
    y = CreateStatRow(panel, "sp", "spell power", y)

    y = y - 4

    -- 4. defense
    y = CreateCategoryHeader(panel, "defense", y, 0.50, 0.70, 0.90)
    y = CreateStatRow(panel, "armor", "armor", y)
    y = CreateStatRow(panel, "dodge", "dodge", y)
    y = CreateStatRow(panel, "parry", "parry", y)
    y = CreateStatRow(panel, "block", "block", y)

    y = y - 4

    -- 5. utility
    y = CreateCategoryHeader(panel, "utility", y, 0.90, 0.80, 0.40)
    y = CreateStatRow(panel, "movement", "speed", y)
    y = CreateStatRow(panel, "durability", "durability", y)
    y = CreateStatRow(panel, "leech", "leech", y)
    y = CreateStatRow(panel, "avoidance", "avoidance", y)

    return panel
end

local function UpdateStatsPanel()
    if InCombatLockdown() then return end
    local ffd = GetFFD(PaperDollFrame)
    local panel = ffd.statsPanel
    if not panel or not panel:IsShown() then return end

    -- average item level
    local avgEquipped = GetAverageItemLevel()
    if issecretvalue(avgEquipped) then
        ffd.statsIlvlHeader:SetText(avgEquipped)
    else
        ffd.statsIlvlHeader:SetText(string_format("%.2f", avgEquipped or 0))
    end

    -- m+ score subtitle
    if ffd.statsMplusSubtitle then
        local mplus = 0
        if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
            mplus = C_ChallengeMode.GetOverallDungeonScore() or 0
        end
        if mplus and not issecretvalue(mplus) and mplus > 0 then
            ffd.statsMplusSubtitle:SetText(string_format("m+ score: %d", mplus))
            ffd.statsMplusSubtitle:Show()
        else
            ffd.statsMplusSubtitle:SetText("")
            ffd.statsMplusSubtitle:Hide()
        end
    end

    -- primary attribute
    local spec = GetSpecialization()
    local primaryID = 1
    if spec and spec > 0 then
        local _, _, _, _, _, stat = GetSpecializationInfo(spec)
        primaryID = stat or 1
    end
    local statName = "strength"
    if primaryID == 2 then statName = "agility"
    elseif primaryID == 4 then statName = "intellect"
    end

    local statVal = UnitStat("player", primaryID)
    local rowPrimary = statsRows["primary"]
    if rowPrimary then
        rowPrimary.label:SetText(statName)
        if issecretvalue(statVal) then
            rowPrimary.value:SetText(statVal)
        else
            rowPrimary.value:SetText(BreakUpLargeNumbers(statVal or 0))
        end
    end

    -- stamina & health
    local stam = UnitStat("player", 3)
    if statsRows["stamina"] then
        if issecretvalue(stam) then
            statsRows["stamina"].value:SetText(stam)
        else
            statsRows["stamina"].value:SetText(BreakUpLargeNumbers(stam or 0))
        end
    end

    local hp = UnitHealthMax("player")
    if statsRows["health"] then
        if issecretvalue(hp) then
            statsRows["health"].value:SetText(hp)
        else
            statsRows["health"].value:SetText(BreakUpLargeNumbers(hp or 0))
        end
    end

    -- secondaries
    if statsRows["crit"] then
        local crit = GetCritChance()
        statsRows["crit"].value:SetText(string_format("%.2f%%", crit or 0))
    end

    if statsRows["haste"] then
        local h = GetHaste()
        statsRows["haste"].value:SetText(string_format("%.2f%%", h or 0))
    end

    if statsRows["mastery"] then
        local m = GetMasteryEffect()
        statsRows["mastery"].value:SetText(string_format("%.2f%%", m or 0))
    end

    if statsRows["versatility"] then
        local v = (GetCombatRatingBonus(29) or 0) + (GetVersatilityBonus(29) or 0)
        statsRows["versatility"].value:SetText(string_format("%.2f%%", v or 0))
    end

    -- attack & spell
    local ap = UnitAttackPower("player")
    if statsRows["ap"] then
        if issecretvalue(ap) then
            statsRows["ap"].value:SetText(ap)
        else
            statsRows["ap"].value:SetText(BreakUpLargeNumbers(ap or 0))
        end
    end

    local mSpeed, oSpeed = UnitAttackSpeed("player")
    if statsRows["speed"] then
        if oSpeed and oSpeed > 0 then
            statsRows["speed"].value:SetText(string_format("%.2f / %.2f", mSpeed or 0, oSpeed))
        else
            statsRows["speed"].value:SetText(string_format("%.2f", mSpeed or 0))
        end
    end

    local sp = GetSpellBonusDamage(7) or 0
    if statsRows["sp"] then
        statsRows["sp"].value:SetText(BreakUpLargeNumbers(sp))
    end

    -- defense
    local _, armor = UnitArmor("player")
    if statsRows["armor"] then
        if issecretvalue(armor) then
            statsRows["armor"].value:SetText(armor)
        else
            statsRows["armor"].value:SetText(BreakUpLargeNumbers(armor or 0))
        end
    end

    if statsRows["dodge"] then
        statsRows["dodge"].value:SetText(string_format("%.2f%%", GetDodgeChance() or 0))
    end

    if statsRows["parry"] then
        statsRows["parry"].value:SetText(string_format("%.2f%%", GetParryChance() or 0))
    end

    if statsRows["block"] then
        statsRows["block"].value:SetText(string_format("%.2f%%", GetBlockChance() or 0))
    end

    -- utility & durability
    local durPct, repairCost = GetTotalDurabilityAndRepairCost()
    if statsRows["durability"] then
        local costStr = FormatMoneyCompact(repairCost)
        if costStr ~= "" then
            statsRows["durability"].value:SetText(string_format("%d%% (%s)", durPct, costStr))
        else
            statsRows["durability"].value:SetText(string_format("%d%%", durPct))
        end
    end

    if statsRows["movement"] then
        local currentSpeed, runSpeed, flightSpeed, swimSpeed = GetUnitSpeed("player")
        local speed = runSpeed or 7
        if IsSwimming and IsSwimming() and swimSpeed and swimSpeed > 0 then
            speed = swimSpeed
        elseif IsFlying and IsFlying() and flightSpeed and flightSpeed > 0 then
            speed = flightSpeed
        elseif currentSpeed and currentSpeed > speed then
            speed = currentSpeed
        end
        local pct = math_floor((speed / 7) * 100 + 0.5)
        statsRows["movement"].value:SetText(string_format("%d%%", pct))
    end

    if statsRows["leech"] then
        local l = GetLifesteal() or 0
        statsRows["leech"].value:SetText(string_format("%.2f%%", l))
    end

    if statsRows["avoidance"] then
        local a = GetAvoidance() or 0
        statsRows["avoidance"].value:SetText(string_format("%.2f%%", a))
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 3D player model setup (interactive drag-to-rotate & native controls)
-- ─────────────────────────────────────────────────────────────────────────────
local function KillModelSceneBackgrounds()
    if CharacterModelScene then
        if CharacterModelScene.SetBackdrop then
            CharacterModelScene:SetBackdrop(nil)
        end
        for _, r in ipairs({ CharacterModelScene:GetRegions() }) do
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                r:SetTexture(nil)
                r:SetColorTexture(0, 0, 0, 0)
                r:SetAlpha(0)
                r:Hide()
                if not r._sfuiSuppressed then
                    r._sfuiSuppressed = true
                    hooksecurefunc(r, "Show", function(self) self:Hide() end)
                    hooksecurefunc(r, "SetShown", function(self, shown) if shown then self:Hide() end end)
                    hooksecurefunc(r, "SetAlpha", function(self, a) if a > 0 then self:SetAlpha(0) end end)
                    hooksecurefunc(r, "SetTexture", function(self, tex) if tex ~= nil then self:SetTexture(nil) end end)
                    hooksecurefunc(r, "SetColorTexture", function(self, cr, cg, cb, ca)
                        if (ca or 1) > 0 then self:SetColorTexture(0, 0, 0, 0) end
                    end)
                end
            end
        end
    end

    if PaperDollFrame then
        for _, r in ipairs({ PaperDollFrame:GetRegions() }) do
            if r and r.IsObjectType and r:IsObjectType("Texture") then
                r:SetTexture(nil)
                r:SetColorTexture(0, 0, 0, 0)
                r:SetAlpha(0)
                r:Hide()
                if not r._sfuiSuppressed then
                    r._sfuiSuppressed = true
                    hooksecurefunc(r, "Show", function(self) self:Hide() end)
                    hooksecurefunc(r, "SetShown", function(self, shown) if shown then self:Hide() end end)
                    hooksecurefunc(r, "SetAlpha", function(self, a) if a > 0 then self:SetAlpha(0) end end)
                    hooksecurefunc(r, "SetTexture", function(self, tex) if tex ~= nil then self:SetTexture(nil) end end)
                end
            end
        end
    end

    if PaperDollSidebarTabs then
        PaperDollSidebarTabs:Hide()
        PaperDollSidebarTabs:SetAlpha(0)
    end

    local innerBorders = {
        _G.PaperDollInnerBorderTopLeft,
        _G.PaperDollInnerBorderTopRight,
        _G.PaperDollInnerBorderBottomLeft,
        _G.PaperDollInnerBorderBottomRight,
        _G.PaperDollInnerBorderLeft,
        _G.PaperDollInnerBorderRight,
        _G.PaperDollInnerBorderTop,
        _G.PaperDollInnerBorderBottom,
        _G.PaperDollInnerBorderBottom2,
    }
    for _, border in ipairs(innerBorders) do
        if border then
            border:SetTexture(nil)
            border:SetColorTexture(0, 0, 0, 0)
            border:SetAlpha(0)
            border:Hide()
        end
    end

    -- remove ragdoll manipulation buttons entirely
    if CharacterModelScene and CharacterModelScene.ControlFrame then
        local control = CharacterModelScene.ControlFrame
        control:Hide()
        control:SetAlpha(0)
        control:EnableMouse(false)
        control:ClearAllPoints()
        if not control._sfuiHidden then
            control._sfuiHidden = true
            control:HookScript("OnShow", function(self)
                self:Hide()
            end)
        end
    end
end

if _G.SetPaperDollBackground then
    hooksecurefunc("SetPaperDollBackground", KillModelSceneBackgrounds)
end

if _G.PaperDollBgDesaturate then
    hooksecurefunc("PaperDollBgDesaturate", KillModelSceneBackgrounds)
end

local function SetupPlayerModel()
    if not CharacterModelScene then return end

    local canvas = EnsureSheetFrame()
    CharacterModelScene:ClearAllPoints()
    CharacterModelScene:SetPoint("TOPLEFT", canvas, "TOPLEFT", 190, -42)
    CharacterModelScene:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMLEFT", 480, 50)
    CharacterModelScene:SetFrameStrata("MEDIUM")
    CharacterModelScene:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 5)
    CharacterModelScene:EnableMouse(true)
    CharacterModelScene:Show()

    if PaperDollItemsFrame then
        PaperDollItemsFrame:EnableMouse(false)
    end

    if not CharacterModelScene._sfuiKillBgHooked then
        CharacterModelScene._sfuiKillBgHooked = true
        CharacterModelScene:HookScript("OnShow", KillModelSceneBackgrounds)
    end

    if PaperDollFrame and not PaperDollFrame._sfuiKillBgHooked then
        PaperDollFrame._sfuiKillBgHooked = true
        PaperDollFrame:HookScript("OnShow", KillModelSceneBackgrounds)
    end

    KillModelSceneBackgrounds()

    -- forward mouse scripts to native Blizzard PanningModelSceneMixin / CharacterModelSceneMixin
    CharacterModelScene:SetScript("OnMouseDown", function(self, button)
        if self.OnMouseDown then self:OnMouseDown(button) end
    end)
    CharacterModelScene:SetScript("OnMouseUp", function(self, button)
        if self.OnMouseUp then self:OnMouseUp(button) end
    end)
    CharacterModelScene:SetScript("OnMouseWheel", function(self, delta)
        if self.OnMouseWheel then self:OnMouseWheel(delta) end
    end)
    CharacterModelScene:SetScript("OnEnter", function(self)
        if self.OnEnter then self:OnEnter() end
    end)
    CharacterModelScene:SetScript("OnLeave", function(self)
        if self.OnLeave then self:OnLeave() end
    end)
    CharacterModelScene:SetScript("OnUpdate", function(self, elapsed)
        if self.OnUpdate then self:OnUpdate(elapsed) end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- sub-panes management (reputation & currency clean cards, docked details & styling)
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateSubPaneCard(parent, titleText, point, relPoint, x, y, width, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint(point, parent, relPoint, x, y)
    card:SetSize(width, height)
    card:SetFrameStrata("LOW")
    card:SetFrameLevel(2)

    if sfui.theme and sfui.theme.ApplyCardStyle then
        sfui.theme.ApplyCardStyle(card)
    else
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        card:SetBackdropColor(0.035, 0.035, 0.045, 0.88)
        card:SetBackdropBorderColor(0.12, 0.12, 0.16, 0.95)
    end

    local headerBar = CreateFrame("Frame", nil, card)
    headerBar:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    headerBar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
    headerBar:SetHeight(22)
    headerBar:SetFrameLevel(card:GetFrameLevel() + 5)

    local hbg = headerBar:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.08, 0.08, 0.11, 0.95)

    local hline = headerBar:CreateTexture(nil, "ARTWORK")
    hline:SetHeight(1)
    hline:SetPoint("BOTTOMLEFT", headerBar, "BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
    hline:SetColorTexture(0.20, 0.20, 0.26, 0.8)

    local label = headerBar:CreateFontString(nil, "OVERLAY")
    StripFont(label, 10)
    label:SetPoint("LEFT", headerBar, "LEFT", 10, 0)
    label:SetTextColor(0.85, 0.85, 0.9, 1)
    label:SetText(titleText:lower())

    card.headerBar = headerBar
    card.headerLabel = label

    return card
end

local function SkinCheckbox(cb, labelText)
    if not cb or cb.sfuiSkinned then return end
    cb.sfuiSkinned = true

    cb:SetSize(18, 18)
    if cb.SetNormalTexture then cb:SetNormalTexture("") end
    if cb.SetPushedTexture then cb:SetPushedTexture("") end

    if not cb.sfuiBg then
        local bg = cb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.11, 0.95)
        cb.sfuiBg = bg
    end

    if not cb.borders then
        common.create_border(cb, 1, { 0.22, 0.22, 0.28, 1 })
    end

    local chk = cb:GetCheckedTexture()
    if chk then
        chk:SetTexture("Interface\\Buttons\\WHITE8x8")
        chk:SetVertexColor(0.25, 0.85, 1.0, 1)
        chk:ClearAllPoints()
        chk:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
        chk:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    end

    local hl = cb:GetHighlightTexture()
    if hl then
        hl:SetTexture("Interface\\Buttons\\WHITE8x8")
        hl:SetVertexColor(1, 1, 1, 0.12)
        hl:ClearAllPoints()
        hl:SetAllPoints(cb)
    end

    local lbl = cb.text or cb.Label or cb.label
    if lbl then
        StripFont(lbl, 11)
        lbl:ClearAllPoints()
        lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        if labelText then
            lbl:SetText(labelText:lower())
        end
    end
end

local function SkinActionButton(btn, labelText)
    if not btn or btn.sfuiSkinned then return end
    btn.sfuiSkinned = true

    if btn.Left then btn.Left:Hide() end
    if btn.Right then btn.Right:Hide() end
    if btn.Middle then btn.Middle:Hide() end

    common.set_pixel_snapping(btn)
    if sfui.theme and sfui.theme.ApplyButtonStyle then
        sfui.theme.ApplyButtonStyle(btn, false)
        if sfui.theme.RegisterButton then
            sfui.theme.RegisterButton(btn, false)
        end
    end

    local fs = btn:GetFontString()
    if fs then
        StripFont(fs, 11)
        if labelText then
            fs:SetText(labelText:lower())
        end
    end
end

local function SkinReputationEntry(button)
    if not button then return end

    if button.SetFrameStrata then button:SetFrameStrata("HIGH") end
    if button.SetFrameLevel then button:SetFrameLevel(28) end

    if button.Content then
        local content = button.Content
        if content.SetFrameStrata then content:SetFrameStrata("HIGH") end
        if content.SetFrameLevel then content:SetFrameLevel(29) end

        if content.Name then
            StripFont(content.Name, 11)
            content.Name:SetTextColor(0.95, 0.95, 0.98, 1)
            content.Name:SetDrawLayer("OVERLAY", 7)
        end

        local bar = content.ReputationBar
        if bar then
            if bar.SetFrameStrata then bar:SetFrameStrata("HIGH") end
            if bar.SetFrameLevel then bar:SetFrameLevel(30) end
            bar:SetHeight(15)
            bar:SetWidth(180)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")

            if bar.LeftTexture then bar.LeftTexture:Hide() end
            if bar.RightTexture then bar.RightTexture:Hide() end

            if bar.Background then
                bar.Background:SetColorTexture(0.06, 0.06, 0.08, 0.85)
            end

            if bar.BarText then
                StripFont(bar.BarText, 10)
                bar.BarText:SetTextColor(1, 1, 1, 1)
                bar.BarText:SetDrawLayer("OVERLAY", 7)
                if not bar.BarText.sfuiHooked then
                    bar.BarText.sfuiHooked = true
                    hooksecurefunc(bar.BarText, "SetText", function(self, text)
                        if text and not issecretvalue(text) and type(text) == "string" and not self.sfuiFormatting then
                            self.sfuiFormatting = true
                            self:SetText(text:lower())
                            self.sfuiFormatting = false
                        end
                    end)
                end
            end

            if not bar.borders then
                common.create_border(bar, 1, { 0, 0, 0, 0.95 })
                if bar.borders then
                    for _, b in ipairs(bar.borders) do
                        b:SetDrawLayer("OVERLAY", 2)
                    end
                end
            end
        end

        if content.ParagonIcon and content.ParagonIcon.SetFrameLevel then
            content.ParagonIcon:SetFrameLevel(31)
        end

        if content.AccountWideIcon and content.AccountWideIcon.SetFrameLevel then
            content.AccountWideIcon:SetFrameLevel(31)
        end

        if content.BackgroundHighlight then
            if content.BackgroundHighlight.Left then content.BackgroundHighlight.Left:Hide() end
            if content.BackgroundHighlight.Right then content.BackgroundHighlight.Right:Hide() end
            if content.BackgroundHighlight.Middle then content.BackgroundHighlight.Middle:Hide() end
            if not content.BackgroundHighlight.sfuiFill then
                local fill = content.BackgroundHighlight:CreateTexture(nil, "BACKGROUND")
                fill:SetAllPoints()
                fill:SetColorTexture(1, 1, 1, 0.08)
                content.BackgroundHighlight.sfuiFill = fill
            end
        end
    elseif button.Left and button.Right and button.Middle then
        button.Left:SetAlpha(0)
        button.Right:SetAlpha(0)
        button.Middle:SetAlpha(0)

        if not button.sfuiHeaderBg then
            local hbg = button:CreateTexture(nil, "BACKGROUND")
            hbg:SetAllPoints()
            hbg:SetColorTexture(0.09, 0.09, 0.13, 0.9)
            button.sfuiHeaderBg = hbg
        end

        if button.Name then
            StripFont(button.Name, 11)
            button.Name:SetTextColor(0.95, 0.82, 0.45, 1)
            button.Name:SetDrawLayer("OVERLAY", 7)
        end
    end

    if button.ToggleCollapseButton and button.ToggleCollapseButton.SetFrameLevel then
        button.ToggleCollapseButton:SetFrameLevel(31)
    end
end

local function SkinTokenEntry(button)
    if not button then return end

    if button.SetFrameStrata then button:SetFrameStrata("HIGH") end
    if button.SetFrameLevel then button:SetFrameLevel(28) end

    if button.Content then
        local content = button.Content
        if content.SetFrameStrata then content:SetFrameStrata("HIGH") end
        if content.SetFrameLevel then content:SetFrameLevel(29) end

        if content.Name then
            StripFont(content.Name, 11)
            content.Name:SetTextColor(0.95, 0.95, 0.98, 1)
            content.Name:SetDrawLayer("OVERLAY", 7)
        end

        if content.Count then
            StripFont(content.Count, 11)
            content.Count:SetTextColor(1, 1, 1, 1)
            content.Count:SetDrawLayer("OVERLAY", 7)
        end

        if content.CurrencyIcon then
            content.CurrencyIcon:SetSize(18, 18)
            content.CurrencyIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            content.CurrencyIcon:SetDrawLayer("ARTWORK", 2)
            if not content.iconBorderFrame then
                local f = CreateFrame("Frame", nil, content)
                f:SetAllPoints(content.CurrencyIcon)
                f:SetFrameLevel(content:GetFrameLevel() + 2)
                common.create_border(f, 1, { 0, 0, 0, 0.95 })
                content.iconBorderFrame = f
            end
        end

        if content.AccountWideIcon and content.AccountWideIcon.SetFrameLevel then
            content.AccountWideIcon:SetFrameLevel(31)
        end

        if content.BackgroundHighlight then
            if content.BackgroundHighlight.Left then content.BackgroundHighlight.Left:Hide() end
            if content.BackgroundHighlight.Right then content.BackgroundHighlight.Right:Hide() end
            if content.BackgroundHighlight.Middle then content.BackgroundHighlight.Middle:Hide() end
            if not content.BackgroundHighlight.sfuiFill then
                local fill = content.BackgroundHighlight:CreateTexture(nil, "BACKGROUND")
                fill:SetAllPoints()
                fill:SetColorTexture(1, 1, 1, 0.08)
                content.BackgroundHighlight.sfuiFill = fill
            end
        end
    elseif button.Text and button.ToggleCollapseButton then
        if not button.sfuiHeaderBg then
            local hbg = button:CreateTexture(nil, "BACKGROUND")
            hbg:SetAllPoints()
            hbg:SetColorTexture(0.09, 0.09, 0.13, 0.9)
            button.sfuiHeaderBg = hbg
        end

        StripFont(button.Text, 11)
        button.Text:SetTextColor(0.95, 0.82, 0.45, 1)
        button.Text:SetDrawLayer("OVERLAY", 7)
    end

    if button.ToggleCollapseButton and button.ToggleCollapseButton.SetFrameLevel then
        button.ToggleCollapseButton:SetFrameLevel(31)
    end
end

local repSetup = false
local function SetupReputationFrame(canvas)
    if not ReputationFrame then return end
    if repSetup then
        if ReputationFrame.SetUsingParentLevel then ReputationFrame:SetUsingParentLevel(false) end
        ReputationFrame:SetFrameStrata("MEDIUM")
        ReputationFrame:SetFrameLevel(10)
        return
    end
    repSetup = true

    if ReputationFrame.SetUsingParentLevel then
        ReputationFrame:SetUsingParentLevel(false)
    end

    for _, r in ipairs({ ReputationFrame:GetRegions() }) do
        if r:IsObjectType("Texture") then r:Hide() end
    end

    ReputationFrame:ClearAllPoints()
    ReputationFrame:SetAllPoints(canvas)
    ReputationFrame:SetFrameStrata("MEDIUM")
    ReputationFrame:SetFrameLevel(10)

    local listCard = CreateSubPaneCard(ReputationFrame, "factions", "TOPLEFT", "TOPLEFT", 12, -45, 435, 450)
    listCard:SetFrameStrata("LOW")
    listCard:SetFrameLevel(2)
    ReputationFrame.sfuiListCard = listCard

    local detailCard = CreateSubPaneCard(ReputationFrame, "faction details", "TOPRIGHT", "TOPRIGHT", -12, -45, 240, 450)
    detailCard:SetFrameStrata("LOW")
    detailCard:SetFrameLevel(2)
    ReputationFrame.sfuiDetailCard = detailCard

    local promptContainer = CreateFrame("Frame", nil, detailCard)
    promptContainer:SetAllPoints(detailCard)
    promptContainer:SetFrameStrata("HIGH")
    promptContainer:SetFrameLevel(25)

    local prompt = promptContainer:CreateFontString(nil, "OVERLAY")
    StripFont(prompt, 10)
    prompt:SetTextColor(0.85, 0.85, 0.90, 1)
    prompt:SetPoint("CENTER", promptContainer, "CENTER", 0, 0)
    prompt:SetWidth(210)
    prompt:SetJustifyH("CENTER")
    prompt:SetText("select a faction from the list to view standing, toggle at war, or view renown.")
    detailCard.emptyPrompt = promptContainer

    if ReputationFrame.ScrollBox then
        ReputationFrame.ScrollBox:ClearAllPoints()
        ReputationFrame.ScrollBox:SetPoint("TOPLEFT", listCard, "TOPLEFT", 6, -26)
        ReputationFrame.ScrollBox:SetPoint("BOTTOMRIGHT", listCard, "BOTTOMRIGHT", -22, 6)
        ReputationFrame.ScrollBox:SetFrameStrata("HIGH")
        ReputationFrame.ScrollBox:SetFrameLevel(25)

        if ReputationFrame.ScrollBox.ScrollTarget then
            ReputationFrame.ScrollBox.ScrollTarget:SetFrameStrata("HIGH")
            ReputationFrame.ScrollBox.ScrollTarget:SetFrameLevel(26)
        end

        if ReputationFrame.ScrollBar then
            ReputationFrame.ScrollBar:ClearAllPoints()
            ReputationFrame.ScrollBar:SetPoint("TOPLEFT", ReputationFrame.ScrollBox, "TOPRIGHT", 4, 0)
            ReputationFrame.ScrollBar:SetPoint("BOTTOMLEFT", ReputationFrame.ScrollBox, "BOTTOMRIGHT", 4, 0)
            ReputationFrame.ScrollBar:SetFrameStrata("HIGH")
            ReputationFrame.ScrollBar:SetFrameLevel(26)
            if common and common.style_scrollbar then
                common.style_scrollbar(ReputationFrame.ScrollBar)
            end
        end

        if ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnDataRangeChanged then
            ReputationFrame.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, function()
                ReputationFrame.ScrollBox:ForEachFrame(SkinReputationEntry)
            end, ReputationFrame)
        end
    end

    if ReputationFrame.filterDropdown then
        ReputationFrame.filterDropdown:ClearAllPoints()
        ReputationFrame.filterDropdown:SetPoint("TOPRIGHT", listCard, "TOPRIGHT", 0, 28)
        ReputationFrame.filterDropdown:SetFrameStrata("HIGH")
        ReputationFrame.filterDropdown:SetFrameLevel(40)
    end

    local detail = (ReputationFrame and ReputationFrame.ReputationDetailFrame) or _G.ReputationDetailFrame
    if detail then
        if detail.SetUsingParentLevel then detail:SetUsingParentLevel(false) end
        detail:SetFrameStrata("HIGH")
        detail:SetFrameLevel(25)
        detail:ClearAllPoints()
        detail:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 12, -28)
        detail:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -12, 12)

        if detail.Border then detail.Border:Hide() end
        if detail.Divider then detail.Divider:Hide() end
        if detail.CloseButton then detail.CloseButton:Hide() end

        for _, r in ipairs({ detail:GetRegions() }) do
            if r:IsObjectType("Texture") and r ~= detail.Divider then
                r:Hide()
            end
        end

        if detail.Title then
            detail.Title:ClearAllPoints()
            detail.Title:SetPoint("TOPLEFT", detail, "TOPLEFT", 4, -4)
            StripFont(detail.Title, 13)
            detail.Title:SetTextColor(1, 0.85, 0.35, 1)
        end

        if detail.ScrollingDescription then
            detail.ScrollingDescription:SetFrameStrata("HIGH")
            detail.ScrollingDescription:SetFrameLevel(27)
            detail.ScrollingDescription:ClearAllPoints()
            detail.ScrollingDescription:SetPoint("TOPLEFT", detail.Title, "BOTTOMLEFT", 0, -8)
            detail.ScrollingDescription:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
            detail.ScrollingDescription:SetHeight(160)
        end

        if detail.ScrollingDescriptionScrollBar and detail.ScrollingDescription then
            detail.ScrollingDescriptionScrollBar:SetFrameStrata("HIGH")
            detail.ScrollingDescriptionScrollBar:SetFrameLevel(28)
            detail.ScrollingDescriptionScrollBar:ClearAllPoints()
            detail.ScrollingDescriptionScrollBar:SetPoint("TOPLEFT", detail.ScrollingDescription, "TOPRIGHT", 4, 0)
            detail.ScrollingDescriptionScrollBar:SetPoint("BOTTOMLEFT", detail.ScrollingDescription, "BOTTOMRIGHT", 4, 0)
            if common and common.style_scrollbar then
                common.style_scrollbar(detail.ScrollingDescriptionScrollBar)
            end
        end

        if detail.AtWarCheckbox then
            detail.AtWarCheckbox:SetFrameStrata("HIGH")
            detail.AtWarCheckbox:SetFrameLevel(28)
            detail.AtWarCheckbox:ClearAllPoints()
            detail.AtWarCheckbox:SetPoint("TOPLEFT", detail.ScrollingDescription, "BOTTOMLEFT", 0, -10)
            SkinCheckbox(detail.AtWarCheckbox, "at war")
        end

        if detail.MakeInactiveCheckbox then
            detail.MakeInactiveCheckbox:SetFrameStrata("HIGH")
            detail.MakeInactiveCheckbox:SetFrameLevel(28)
            detail.MakeInactiveCheckbox:ClearAllPoints()
            detail.MakeInactiveCheckbox:SetPoint("TOPLEFT", detail.AtWarCheckbox, "BOTTOMLEFT", 0, -6)
            SkinCheckbox(detail.MakeInactiveCheckbox, "inactive")
        end

        if detail.WatchFactionCheckbox then
            detail.WatchFactionCheckbox:SetFrameStrata("HIGH")
            detail.WatchFactionCheckbox:SetFrameLevel(28)
            detail.WatchFactionCheckbox:ClearAllPoints()
            detail.WatchFactionCheckbox:SetPoint("TOPLEFT", detail.MakeInactiveCheckbox, "BOTTOMLEFT", 0, -6)
            SkinCheckbox(detail.WatchFactionCheckbox, "show as experience bar")
        end

        if detail.ViewRenownButton then
            detail.ViewRenownButton:SetFrameStrata("HIGH")
            detail.ViewRenownButton:SetFrameLevel(28)
            detail.ViewRenownButton:ClearAllPoints()
            detail.ViewRenownButton:SetPoint("BOTTOM", detailCard, "BOTTOM", 0, 12)
            detail.ViewRenownButton:SetSize(210, 22)
            SkinActionButton(detail.ViewRenownButton, "view renown")
        end

        hooksecurefunc(detail, "Refresh", function(self)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 12, -28)
            self:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -12, 12)
            if self.Title then
                StripFont(self.Title, 13)
                local t = self.Title:GetText()
                if t and not issecretvalue(t) and type(t) == "string" then
                    self.Title:SetText(t:lower())
                end
            end
        end)

        detail:HookScript("OnShow", function()
            if detailCard.emptyPrompt then detailCard.emptyPrompt:Hide() end
        end)
        detail:HookScript("OnHide", function()
            if detailCard.emptyPrompt then detailCard.emptyPrompt:Show() end
        end)
    end
end

local tokenSetup = false
local function SetupTokenFrame(canvas)
    if not TokenFrame then return end
    if tokenSetup then
        if TokenFrame.SetUsingParentLevel then TokenFrame:SetUsingParentLevel(false) end
        TokenFrame:SetFrameStrata("MEDIUM")
        TokenFrame:SetFrameLevel(10)
        return
    end
    tokenSetup = true

    if TokenFrame.SetUsingParentLevel then
        TokenFrame:SetUsingParentLevel(false)
    end

    for _, r in ipairs({ TokenFrame:GetRegions() }) do
        if r:IsObjectType("Texture") then r:Hide() end
    end

    TokenFrame:ClearAllPoints()
    TokenFrame:SetAllPoints(canvas)
    TokenFrame:SetFrameStrata("MEDIUM")
    TokenFrame:SetFrameLevel(10)

    local listCard = CreateSubPaneCard(TokenFrame, "currencies", "TOPLEFT", "TOPLEFT", 12, -45, 435, 450)
    listCard:SetFrameStrata("LOW")
    listCard:SetFrameLevel(2)
    TokenFrame.sfuiListCard = listCard

    local detailCard = CreateSubPaneCard(TokenFrame, "currency options", "TOPRIGHT", "TOPRIGHT", -12, -45, 240, 450)
    detailCard:SetFrameStrata("LOW")
    detailCard:SetFrameLevel(2)
    TokenFrame.sfuiDetailCard = detailCard

    local promptContainer = CreateFrame("Frame", nil, detailCard)
    promptContainer:SetAllPoints(detailCard)
    promptContainer:SetFrameStrata("HIGH")
    promptContainer:SetFrameLevel(25)

    local prompt = promptContainer:CreateFontString(nil, "OVERLAY")
    StripFont(prompt, 10)
    prompt:SetTextColor(0.85, 0.85, 0.90, 1)
    prompt:SetPoint("CENTER", promptContainer, "CENTER", 0, 0)
    prompt:SetWidth(210)
    prompt:SetJustifyH("CENTER")
    prompt:SetText("click a currency on the left to configure backpack tracking or mark as unused.")
    detailCard.emptyPrompt = promptContainer

    if TokenFrame.ScrollBox then
        TokenFrame.ScrollBox:ClearAllPoints()
        TokenFrame.ScrollBox:SetPoint("TOPLEFT", listCard, "TOPLEFT", 6, -26)
        TokenFrame.ScrollBox:SetPoint("BOTTOMRIGHT", listCard, "BOTTOMRIGHT", -22, 6)
        TokenFrame.ScrollBox:SetFrameStrata("HIGH")
        TokenFrame.ScrollBox:SetFrameLevel(25)

        if TokenFrame.ScrollBox.ScrollTarget then
            TokenFrame.ScrollBox.ScrollTarget:SetFrameStrata("HIGH")
            TokenFrame.ScrollBox.ScrollTarget:SetFrameLevel(26)
        end

        if TokenFrame.ScrollBar then
            TokenFrame.ScrollBar:ClearAllPoints()
            TokenFrame.ScrollBar:SetPoint("TOPLEFT", TokenFrame.ScrollBox, "TOPRIGHT", 4, 0)
            TokenFrame.ScrollBar:SetPoint("BOTTOMLEFT", TokenFrame.ScrollBox, "BOTTOMRIGHT", 4, 0)
            TokenFrame.ScrollBar:SetFrameStrata("HIGH")
            TokenFrame.ScrollBar:SetFrameLevel(26)
            if common and common.style_scrollbar then
                common.style_scrollbar(TokenFrame.ScrollBar)
            end
        end

        if ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnDataRangeChanged then
            TokenFrame.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, function()
                TokenFrame.ScrollBox:ForEachFrame(SkinTokenEntry)
            end, TokenFrame)
        end
    end

    if TokenFrame.filterDropdown then
        TokenFrame.filterDropdown:ClearAllPoints()
        TokenFrame.filterDropdown:SetPoint("TOPRIGHT", listCard, "TOPRIGHT", 0, 28)
        TokenFrame.filterDropdown:SetFrameStrata("HIGH")
        TokenFrame.filterDropdown:SetFrameLevel(40)
    end

    if TokenFrame.CurrencyTransferLogToggleButton then
        TokenFrame.CurrencyTransferLogToggleButton:ClearAllPoints()
        TokenFrame.CurrencyTransferLogToggleButton:SetPoint("RIGHT", TokenFrame.filterDropdown, "LEFT", -8, 0)
        TokenFrame.CurrencyTransferLogToggleButton:SetFrameStrata("HIGH")
        TokenFrame.CurrencyTransferLogToggleButton:SetFrameLevel(40)
        TokenFrame.CurrencyTransferLogToggleButton:SetSize(120, 22)
        SkinActionButton(TokenFrame.CurrencyTransferLogToggleButton, "transfer log")
    end

    local popup = TokenFramePopup or (TokenFrame and TokenFrame.Popup)
    if popup then
        if popup.SetUsingParentLevel then popup:SetUsingParentLevel(false) end
        popup:SetFrameStrata("HIGH")
        popup:SetFrameLevel(25)
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 12, -28)
        popup:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -12, 12)

        if popup.Border then popup.Border:Hide() end
        if popup.CloseButton then popup.CloseButton:Hide() end

        for _, r in ipairs({ popup:GetRegions() }) do
            if r:IsObjectType("Texture") then r:Hide() end
        end

        if popup.Title then
            popup.Title:ClearAllPoints()
            popup.Title:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4)
            StripFont(popup.Title, 13)
            popup.Title:SetTextColor(1, 0.85, 0.35, 1)
        end

        if popup.InactiveCheckbox then
            popup.InactiveCheckbox:SetFrameStrata("HIGH")
            popup.InactiveCheckbox:SetFrameLevel(28)
            popup.InactiveCheckbox:ClearAllPoints()
            popup.InactiveCheckbox:SetPoint("TOPLEFT", popup.Title, "BOTTOMLEFT", 0, -14)
            SkinCheckbox(popup.InactiveCheckbox, "unused")
        end

        if popup.BackpackCheckbox then
            popup.BackpackCheckbox:SetFrameStrata("HIGH")
            popup.BackpackCheckbox:SetFrameLevel(28)
            popup.BackpackCheckbox:ClearAllPoints()
            popup.BackpackCheckbox:SetPoint("TOPLEFT", popup.InactiveCheckbox, "BOTTOMLEFT", 0, -8)
            SkinCheckbox(popup.BackpackCheckbox, "show on backpack")
        end

        if popup.CurrencyTransferToggleButton then
            popup.CurrencyTransferToggleButton:SetFrameStrata("HIGH")
            popup.CurrencyTransferToggleButton:SetFrameLevel(28)
            popup.CurrencyTransferToggleButton:ClearAllPoints()
            popup.CurrencyTransferToggleButton:SetPoint("TOPLEFT", popup.BackpackCheckbox, "BOTTOMLEFT", 0, -14)
            popup.CurrencyTransferToggleButton:SetSize(220, 24)
            SkinActionButton(popup.CurrencyTransferToggleButton, "transfer currency")
        end

        popup:HookScript("OnShow", function()
            if detailCard.emptyPrompt then detailCard.emptyPrompt:Hide() end
            if popup.Title and TokenFrame.selectedToken and not issecretvalue(TokenFrame.selectedToken) then
                StripFont(popup.Title, 13)
                popup.Title:SetText(TokenFrame.selectedToken:lower())
            end
        end)
        popup:HookScript("OnHide", function()
            if detailCard.emptyPrompt then detailCard.emptyPrompt:Show() end
        end)
    end

    if CurrencyTransferLog then
        CurrencyTransferLog:SetFrameStrata("HIGH")
        CurrencyTransferLog:SetFrameLevel(25)
        CurrencyTransferLog:ClearAllPoints()
        CurrencyTransferLog:SetPoint("TOPLEFT", detailCard, "TOPLEFT", 6, -26)
        CurrencyTransferLog:SetPoint("BOTTOMRIGHT", detailCard, "BOTTOMRIGHT", -6, 6)
        if CurrencyTransferLog.Border then CurrencyTransferLog.Border:Hide() end
    end
end

local function LayoutSubPanes()
    local canvas = EnsureSheetFrame()

    if not InCombatLockdown() then
        if CharacterFrame:GetWidth() ~= PANEL_WIDTH or CharacterFrame:GetHeight() ~= PANEL_HEIGHT then
            CharacterFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        end
    end

    local selectedTab = (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(CharacterFrame)) or 1
    local isRep = (selectedTab == 2) or (CharacterFrame.activeSubframe == "ReputationFrame")
    local isToken = (selectedTab == 3) or (CharacterFrame.activeSubframe == "TokenFrame")

    if isRep then
        SetupReputationFrame(canvas)
        if ReputationFrame then
            if ReputationFrame.SetUsingParentLevel then ReputationFrame:SetUsingParentLevel(false) end
            ReputationFrame:SetFrameStrata("MEDIUM")
            ReputationFrame:SetFrameLevel(10)
            ReputationFrame:ClearAllPoints()
            ReputationFrame:SetAllPoints(canvas)
            ReputationFrame:Show()
            if ReputationFrame.ScrollBox then
                ReputationFrame.ScrollBox:SetFrameStrata("HIGH")
                ReputationFrame.ScrollBox:SetFrameLevel(25)
                if ReputationFrame.ScrollBox.ScrollTarget then
                    ReputationFrame.ScrollBox.ScrollTarget:SetFrameStrata("HIGH")
                    ReputationFrame.ScrollBox.ScrollTarget:SetFrameLevel(26)
                end
                ReputationFrame.ScrollBox:ForEachFrame(SkinReputationEntry)
            end
            if ReputationFrame.ScrollBar then
                ReputationFrame.ScrollBar:SetFrameStrata("HIGH")
                ReputationFrame.ScrollBar:SetFrameLevel(26)
            end
        end
        if TokenFrame then TokenFrame:Hide() end
        if PaperDollFrame then PaperDollFrame:Hide() end

        if CharacterFrameTitleText then
            CharacterFrameTitleText:ClearAllPoints()
            CharacterFrameTitleText:SetPoint("TOP", canvas.headerFrame, "TOP", 0, 0)
            CharacterFrameTitleText:SetJustifyH("CENTER")
            StripFont(CharacterFrameTitleText, 12)
            CharacterFrameTitleText:SetText("reputation")
        end
        if CharacterLevelText then
            CharacterLevelText:SetText("")
            CharacterLevelText:Hide()
        end
    elseif isToken then
        if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_TokenUI") then
            C_AddOns.LoadAddOn("Blizzard_TokenUI")
        end
        SetupTokenFrame(canvas)
        if TokenFrame then
            if TokenFrame.SetUsingParentLevel then TokenFrame:SetUsingParentLevel(false) end
            TokenFrame:SetFrameStrata("MEDIUM")
            TokenFrame:SetFrameLevel(10)
            TokenFrame:ClearAllPoints()
            TokenFrame:SetAllPoints(canvas)
            TokenFrame:Show()
            if TokenFrame.ScrollBox then
                TokenFrame.ScrollBox:SetFrameStrata("HIGH")
                TokenFrame.ScrollBox:SetFrameLevel(25)
                if TokenFrame.ScrollBox.ScrollTarget then
                    TokenFrame.ScrollBox.ScrollTarget:SetFrameStrata("HIGH")
                    TokenFrame.ScrollBox.ScrollTarget:SetFrameLevel(26)
                end
                TokenFrame.ScrollBox:ForEachFrame(SkinTokenEntry)
            end
            if TokenFrame.ScrollBar then
                TokenFrame.ScrollBar:SetFrameStrata("HIGH")
                TokenFrame.ScrollBar:SetFrameLevel(26)
            end
        end
        if ReputationFrame then ReputationFrame:Hide() end
        if PaperDollFrame then PaperDollFrame:Hide() end

        if CharacterFrameTitleText then
            CharacterFrameTitleText:ClearAllPoints()
            CharacterFrameTitleText:SetPoint("TOP", canvas.headerFrame, "TOP", 0, 0)
            CharacterFrameTitleText:SetJustifyH("CENTER")
            StripFont(CharacterFrameTitleText, 12)
            CharacterFrameTitleText:SetText("currency")
        end
        if CharacterLevelText then
            CharacterLevelText:SetText("")
            CharacterLevelText:Hide()
        end
    else
        if ReputationFrame then ReputationFrame:Hide() end
        if TokenFrame then TokenFrame:Hide() end
        if PaperDollFrame then
            if PaperDollFrame.SetUsingParentLevel then PaperDollFrame:SetUsingParentLevel(false) end
            PaperDollFrame:SetFrameStrata("MEDIUM")
            PaperDollFrame:SetFrameLevel(10)
            PaperDollFrame:Show()
            KillModelSceneBackgrounds()
        end
        if PaperDollItemsFrame then
            PaperDollItemsFrame:SetFrameStrata("MEDIUM")
            PaperDollItemsFrame:SetFrameLevel(20)
            PaperDollItemsFrame:Show()
        end

        if CharacterFrameTitleText then
            if canvas.headerFrame then
                CharacterFrameTitleText:SetParent(canvas.headerFrame)
                CharacterFrameTitleText:ClearAllPoints()
                CharacterFrameTitleText:SetPoint("TOP", canvas.headerFrame, "TOP", 0, 0)
            else
                CharacterFrameTitleText:ClearAllPoints()
                CharacterFrameTitleText:SetPoint("TOP", canvas, "TOP", -15, -6)
            end
            CharacterFrameTitleText:SetJustifyH("CENTER")
            StripFont(CharacterFrameTitleText, 12)
            CharacterFrameTitleText:SetDrawLayer("OVERLAY", 7)
            local pvpName = UnitPVPName("player") or UnitName("player") or ""
            CharacterFrameTitleText:SetText(pvpName:lower())
        end
        if CharacterLevelText and CharacterFrameTitleText then
            if canvas.headerFrame then
                CharacterLevelText:SetParent(canvas.headerFrame)
                CharacterLevelText:ClearAllPoints()
                CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -2)
            else
                CharacterLevelText:ClearAllPoints()
                CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -2)
            end
            CharacterLevelText:SetJustifyH("CENTER")
            StripFont(CharacterLevelText, 10)
            CharacterLevelText:SetDrawLayer("OVERLAY", 7)
            CharacterLevelText:Show()
        end
    end

    local tabs = { CharacterFrameTab1, CharacterFrameTab2, CharacterFrameTab3 }
    if sfui.theme and sfui.theme.ApplyTabStyle then
        for i, tab in ipairs(tabs) do
            if tab then
                sfui.theme.ApplyTabStyle(tab, (isRep and i == 2) or (isToken and i == 3) or ((not isRep and not isToken) and i == 1))
            end
        end
    end
end


-- ─────────────────────────────────────────────────────────────────────────────
-- main character sheet refresh
-- ─────────────────────────────────────────────────────────────────────────────
local function RefreshAll()
    if InCombatLockdown() then return end
    if not CharacterFrame:IsShown() then return end

    -- title & subtitle
    if CharacterFrameTitleText then
        local pvpName = UnitPVPName("player") or UnitName("player") or ""
        CharacterFrameTitleText:SetText(pvpName:lower())
    end

    if CharacterLevelText then
        local lvl = UnitLevel("player")
        local _, class = UnitClass("player")
        local spec = GetSpecialization()
        local specName = ""
        if spec and spec > 0 then
            local _, name = GetSpecializationInfo(spec)
            specName = name and (name:lower() .. " ") or ""
        end
        local cColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        local hex = cColor and cColor.colorStr or "ffffffff"
        CharacterLevelText:SetText(string_format("level %s |c%s%s%s|r", tostring(lvl or ""), hex, specName, class and class:lower() or ""))
    end

    -- equipment slots
    for _, slotDef in ipairs(EQUIPMENT_SLOTS) do
        UpdateSlot(slotDef)
    end

    -- stats panel
    UpdateStatsPanel()

    -- align custom sfui header buttons
    if sfui.character and sfui.character.AlignHeaderButtons then
        sfui.character.AlignHeaderButtons()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- initialize frame layout & skinning
-- ─────────────────────────────────────────────────────────────────────────────
local initialized = false
local function InitCharacterSheet()
    if initialized then return end
    if not CharacterFrame then return end
    initialized = true

    local canvas = EnsureSheetFrame()
    canvas:SetFrameLevel(1)

    -- strip default blizzard art
    if CharacterFrame.NineSlice then CharacterFrame.NineSlice:Hide() end
    if CharacterFrame.Background then CharacterFrame.Background:Hide(); CharacterFrame.Background:SetAlpha(0) end
    if CharacterFrame.TitleBg then CharacterFrame.TitleBg:Hide() end
    if CharacterFrame.TopTileStreaks then CharacterFrame.TopTileStreaks:Hide() end
    if CharacterFrame.Portrait then CharacterFrame.Portrait:Hide() end
    if CharacterFramePortrait then CharacterFramePortrait:Hide() end
    if CharacterFrame.PortraitContainer then CharacterFrame.PortraitContainer:Hide() end
    if CharacterFrameInset then
        CharacterFrameInset:Hide()
        if CharacterFrameInset.NineSlice then CharacterFrameInset.NineSlice:Hide() end
        if CharacterFrameInset.Bg then CharacterFrameInset.Bg:Hide() end
    end
    if CharacterFrame.Inset then
        CharacterFrame.Inset:Hide()
        if CharacterFrame.Inset.NineSlice then CharacterFrame.Inset.NineSlice:Hide() end
        if CharacterFrame.Inset.Bg then CharacterFrame.Inset.Bg:Hide() end
    end
    if CharacterFrameInsetRight then
        CharacterFrameInsetRight:Hide()
        if CharacterFrameInsetRight.NineSlice then CharacterFrameInsetRight.NineSlice:Hide() end
        CharacterFrameInsetRight:HookScript("OnShow", function(self) self:Hide() end)
    end
    if CharacterFrameInsetBG then CharacterFrameInsetBG:Hide() end

    -- park blizzard's CharacterStatsPane off-screen safely and suppress
    if CharacterStatsPane then
        CharacterStatsPane:ClearAllPoints()
        CharacterStatsPane:SetPoint("TOPLEFT", CharacterFrame, "BOTTOMLEFT", 0, -10000)
        CharacterStatsPane:Hide()
        CharacterStatsPane:HookScript("OnShow", function(self) self:Hide() end)
    end

    -- resize character frame height
    CharacterFrame:SetHeight(PANEL_HEIGHT)

    -- hide default CharacterFrameBg so theme backdrop on canvas is the sole surface
    if CharacterFrameBg then
        CharacterFrameBg:Hide()
        CharacterFrameBg:SetAlpha(0)
    end

    -- expand PaperDollFrame to fill full sheet canvas and elevate above canvas
    if PaperDollFrame then
        if PaperDollFrame.SetUsingParentLevel then PaperDollFrame:SetUsingParentLevel(false) end
        PaperDollFrame:ClearAllPoints()
        PaperDollFrame:SetAllPoints(canvas)
        PaperDollFrame:SetFrameLevel(canvas:GetFrameLevel() + 5)
    end

    if PaperDollItemsFrame then
        PaperDollItemsFrame:SetFrameLevel(PaperDollFrame:GetFrameLevel() + 10)
    end

    -- dedicated elevated header container for title and level fontstrings (prevents theme occlusion)
    if not canvas.headerFrame then
        local hf = CreateFrame("Frame", nil, canvas)
        hf:SetSize(280, 34)
        hf:SetPoint("TOP", canvas, "TOP", -15, -6)
        hf:SetFrameLevel(canvas:GetFrameLevel() + 25)
        canvas.headerFrame = hf
    end

    -- close button
    if CharacterFrameCloseButton then
        CharacterFrameCloseButton:ClearAllPoints()
        CharacterFrameCloseButton:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -8, -6)
        CharacterFrameCloseButton:SetFrameLevel(canvas:GetFrameLevel() + 25)
    end

    -- title texts centered above 3D model
    if CharacterFrameTitleText then
        CharacterFrameTitleText:SetParent(canvas.headerFrame)
        CharacterFrameTitleText:ClearAllPoints()
        CharacterFrameTitleText:SetPoint("TOP", canvas.headerFrame, "TOP", 0, 0)
        CharacterFrameTitleText:SetJustifyH("CENTER")
        StripFont(CharacterFrameTitleText, 12)
        CharacterFrameTitleText:SetDrawLayer("OVERLAY", 7)
    end

    if CharacterLevelText and CharacterFrameTitleText then
        CharacterLevelText:SetParent(canvas.headerFrame)
        CharacterLevelText:ClearAllPoints()
        CharacterLevelText:SetPoint("TOP", CharacterFrameTitleText, "BOTTOM", 0, -2)
        CharacterLevelText:SetJustifyH("CENTER")
        StripFont(CharacterLevelText, 10)
        CharacterLevelText:SetDrawLayer("OVERLAY", 7)
    end

    -- reposition left slots (head to wrist)
    if CharacterHeadSlot then
        CharacterHeadSlot:ClearAllPoints()
        CharacterHeadSlot:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -42)

        local prev = CharacterHeadSlot
        local leftOrder = {
            CharacterNeckSlot,
            CharacterShoulderSlot,
            CharacterBackSlot,
            CharacterChestSlot,
            CharacterShirtSlot,
            CharacterTabardSlot,
            CharacterWristSlot,
        }
        for _, slot in ipairs(leftOrder) do
            if slot then
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -15)
                prev = slot
            end
        end
    end

    -- reposition right slots (hands to trinket 2)
    if CharacterHandsSlot then
        CharacterHandsSlot:ClearAllPoints()
        CharacterHandsSlot:SetPoint("TOPLEFT", canvas, "TOPLEFT", 482, -42)

        local prev = CharacterHandsSlot
        local rightOrder = {
            CharacterWaistSlot,
            CharacterLegsSlot,
            CharacterFeetSlot,
            CharacterFinger0Slot,
            CharacterFinger1Slot,
            CharacterTrinket0Slot,
            CharacterTrinket1Slot,
        }
        for _, slot in ipairs(rightOrder) do
            if slot then
                slot:ClearAllPoints()
                slot:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -15)
                prev = slot
            end
        end
    end

    -- reposition weapons (mainhand and offhand)
    if CharacterMainHandSlot then
        CharacterMainHandSlot:ClearAllPoints()
        CharacterMainHandSlot:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 120, 12)
    end
    if CharacterSecondaryHandSlot and CharacterMainHandSlot then
        CharacterSecondaryHandSlot:ClearAllPoints()
        CharacterSecondaryHandSlot:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 370, 12)
    end

    -- skin equipment slot item buttons
    for _, slotDef in ipairs(EQUIPMENT_SLOTS) do
        local slotButton = _G[slotDef.name]
        if slotButton then
            SkinSlotButton(slotButton)
        end
    end

    -- hook blizzard item slot updates to maintain sfui square icon skin and borders
    if not PaperDollFrame._sfuiSlotHooked then
        PaperDollFrame._sfuiSlotHooked = true
        hooksecurefunc("PaperDollItemSlotButton_Update", function(slotButton)
            if not slotButton or not slotButton.GetName then return end
            local name = slotButton:GetName()
            if not name then return end
            for _, def in ipairs(EQUIPMENT_SLOTS) do
                if def.name == name then
                    UpdateSlot(def)
                    break
                end
            end
        end)
    end

    -- 3d player model
    SetupPlayerModel()

    -- stats panel (parented to PaperDollFrame to avoid bleed-through to Rep/Currency)
    BuildStatsPanel(PaperDollFrame)

    -- ensure Blizzard_TokenUI is loaded
    if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_TokenUI") then
        C_AddOns.LoadAddOn("Blizzard_TokenUI")
    end

    -- skin tabs with lowercase labels and anchor first tab to canvas bottom
    if CharacterFrameTab1 then
        CharacterFrameTab1:ClearAllPoints()
        CharacterFrameTab1:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 12, 2)
    end

    local tabs = { CharacterFrameTab1, CharacterFrameTab2, CharacterFrameTab3 }
    local tabLabels = { "character", "reputation", "currency" }
    for i, tab in ipairs(tabs) do
        if tab then
            tab:SetFrameStrata("MEDIUM")
            tab:SetFrameLevel(30)
            tab:Show()
            tab:SetText(tabLabels[i])
            if tab.Text then
                tab.Text:SetText(tabLabels[i])
                StripFont(tab.Text, 11)
            end
            if sfui.theme and sfui.theme.ApplyTabStyle then
                sfui.theme.ApplyTabStyle(tab, i == 1)
            end
        end
    end

    if CharacterFrameTab1 then
        CharacterFrameTab1:HookScript("OnClick", function()
            PanelTemplates_SetTab(CharacterFrame, 1)
            CharacterFrame:ShowSubFrame("PaperDollFrame")
            LayoutSubPanes()
            RefreshAll()
        end)
    end

    if CharacterFrameTab2 then
        CharacterFrameTab2:HookScript("OnClick", function()
            PanelTemplates_SetTab(CharacterFrame, 2)
            CharacterFrame:ShowSubFrame("ReputationFrame")
            LayoutSubPanes()
        end)
    end

    if CharacterFrameTab3 then
        CharacterFrameTab3:HookScript("OnClick", function()
            if C_AddOns and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_TokenUI") then
                C_AddOns.LoadAddOn("Blizzard_TokenUI")
            end
            PanelTemplates_SetTab(CharacterFrame, 3)
            CharacterFrame:ShowSubFrame("TokenFrame")
            LayoutSubPanes()
        end)

        hooksecurefunc(CharacterFrameTab3, "Hide", function(self)
            if not self.sfuiForcingShow then
                self.sfuiForcingShow = true
                self:Show()
                self.sfuiForcingShow = false
            end
        end)

        hooksecurefunc(CharacterFrameTab3, "SetShown", function(self, shown)
            if not shown and not self.sfuiForcingShow then
                self.sfuiForcingShow = true
                self:Show()
                self.sfuiForcingShow = false
            end
        end)
    end

    -- register theme directly on the canvas
    if sfui.theme and sfui.theme.RegisterWindow then
        if sfui.theme.UnregisterWindow then
            sfui.theme.UnregisterWindow(CharacterFrame)
        end
        if CharacterFrame.sfuiThemeLayers and CharacterFrame.sfuiThemeLayers.borderFrame then
            CharacterFrame.sfuiThemeLayers.borderFrame:Hide()
        end
        if CharacterFrame.sfuiOldGodLayers and CharacterFrame.sfuiOldGodLayers.borderFrame then
            CharacterFrame.sfuiOldGodLayers.borderFrame:Hide()
        end
        if CharacterFrame.sfuiFallenSanctumLayers and CharacterFrame.sfuiFallenSanctumLayers.borderFrame then
            CharacterFrame.sfuiFallenSanctumLayers.borderFrame:Hide()
        end
        if CharacterFrame.sfuiMawLayers and CharacterFrame.sfuiMawLayers.borderFrame then
            CharacterFrame.sfuiMawLayers.borderFrame:Hide()
        end
        if CharacterFrame.sfuiNecrolordLayers and CharacterFrame.sfuiNecrolordLayers.borderFrame then
            CharacterFrame.sfuiNecrolordLayers.borderFrame:Hide()
        end

        sfui.theme.RegisterWindow(canvas, function(f, curPal)
            if f.sfuiSolidBg and curPal and curPal.backdropColor then
                local c = curPal.backdropColor
                f.sfuiSolidBg:SetColorTexture(c[1], c[2], c[3], c[4] or 0.95)
                f.sfuiSolidBg:Show()
            end
            if CharacterFrameCloseButton and sfui.theme.ApplyCloseButtonStyle then
                sfui.theme.ApplyCloseButtonStyle(CharacterFrameCloseButton)
            end
        end)
    end

    -- secure hooks to keep CharacterFrame size stable and react to subframe switching
    hooksecurefunc(CharacterFrame, "UpdateSize", function(self)
        if not InCombatLockdown() then
            self:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        end
    end)

    hooksecurefunc(CharacterFrame, "ShowSubFrame", function(self, frameName)
        LayoutSubPanes()
    end)

    hooksecurefunc(CharacterFrame, "UpdateTitle", function(self)
        local selectedTab = (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(self)) or 1
        if selectedTab == 2 or self.activeSubframe == "ReputationFrame" then
            if CharacterFrameTitleText then CharacterFrameTitleText:SetText("reputation") end
        elseif selectedTab == 3 or self.activeSubframe == "TokenFrame" then
            if CharacterFrameTitleText then CharacterFrameTitleText:SetText("currency") end
        else
            local pvpName = UnitPVPName("player") or UnitName("player") or ""
            if CharacterFrameTitleText then CharacterFrameTitleText:SetText(pvpName:lower()) end
        end
    end)

    -- hook show & subframe changes
    CharacterFrame:HookScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        end
        canvas:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        canvas:SetFrameStrata("LOW")
        canvas:SetFrameLevel(1)
        canvas:Show()
        if canvas.sfuiSolidBg then canvas.sfuiSolidBg:Show() end
        if PaperDollFrame then
            if PaperDollFrame.SetUsingParentLevel then PaperDollFrame:SetUsingParentLevel(false) end
            PaperDollFrame:SetFrameStrata("MEDIUM")
            PaperDollFrame:SetFrameLevel(10)
        end
        if PaperDollItemsFrame then
            PaperDollItemsFrame:SetFrameStrata("MEDIUM")
            PaperDollItemsFrame:SetFrameLevel(20)
        end
        if canvas.headerFrame then
            canvas.headerFrame:SetFrameStrata("MEDIUM")
            canvas.headerFrame:SetFrameLevel(25)
        end
        if CharacterFrameTab3 then CharacterFrameTab3:Show() end
        KillModelSceneBackgrounds()
        LayoutSubPanes()
        local selectedTab = (PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(self)) or 1
        if selectedTab == 1 then
            RefreshAll()
        end
    end)

    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            KillModelSceneBackgrounds()
            RefreshAll()
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- event dispatcher
-- ─────────────────────────────────────────────────────────────────────────────
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UNIT_STATS")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_MONEY")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventFrame:RegisterEvent("HONOR_XP_UPDATE")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        InitCharacterSheet()
    elseif event == "PLAYER_ENTERING_WORLD" then
        InitCharacterSheet()
        if CharacterFrame and CharacterFrame:IsShown() then
            RefreshAll()
        end
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_TokenUI" then
        if CharacterFrame and CharacterFrame:IsShown() then
            local c = EnsureSheetFrame()
            SetupTokenFrame(c)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_MONEY"
        or event == "UPDATE_INVENTORY_DURABILITY"
        or event == "HONOR_XP_UPDATE"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if CharacterFrame and CharacterFrame:IsShown() then
            RefreshAll()
        end
    elseif (event == "UNIT_STATS" or event == "UNIT_AURA") and arg1 == "player" then
        if CharacterFrame and CharacterFrame:IsShown() then
            UpdateStatsPanel()
        end
    end
end)
