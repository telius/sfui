local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sets = sfui.sets or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/gear/sets.lua
--  In-Game Tier & Dungeon Set Tracker (Tier 0, Forever Tier 0.5, Dungeon Sets)
--  Top-level Adventure Guide tab with live ownership, TSM BoE prices, "run next"
--  farm summary, wishlist batching, dressing-room try-on, and deep-link navigation.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local _G = _G
local CreateFrame = _G.CreateFrame
local GameTooltip = _G.GameTooltip
local UIParent = _G.UIParent
local C_Item = _G.C_Item
local C_Timer = _G.C_Timer
local GetInventoryItemID = _G.GetInventoryItemID
local GetItemInfo = _G.GetItemInfo
local DressUpItemLink = _G.DressUpItemLink
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsControlKeyDown = _G.IsControlKeyDown

local pairs, ipairs, type = _G.pairs, _G.ipairs, _G.type
local tonumber, tostring = _G.tonumber, _G.tostring
local math_floor, math_max, math_min = _G.math.floor, _G.math.max, _G.math.min
local string_format = _G.string.format
local table_sort, table_concat, table_wipe = _G.table.sort, _G.table.concat, _G.table.wipe

local common = sfui.common
local theme = sfui.theme
local colors = sfui.colors
local issecretvalue = (sfui.safety and sfui.safety.issecretvalue) or _G.issecretvalue or function() return false end

local S = sfui.sets
local DATA = function() return sfui.sets_camelot end

local PANEL_W = 844
local CARD_H = 102
local CARD_GAP = 6
local TILE_W = 94
local TILE_H = 66
local TILE_GAP = 4
local MAX_RUN_NEXT_CHIPS = 5
local WISHLIST_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"
local FALLBACK_ICON = 134400

local ROLE_ORDER = { melee = 1, tank = 2, caster = 3, healer = 4 }
local CAT_ORDER = { t0 = 1, t05 = 2, dungeon = 3 }

local DEFAULTS = {
    category     = "all",   -- "all" | "t0" | "t05" | "dungeon"
    classFilter  = "mine",  -- "mine" | "all" | classToken
    wearableOnly = true,
    missingOnly  = false,
}

if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("sets", DEFAULTS)
end

local function DB()
    SfuiDB = SfuiDB or {}
    if type(SfuiDB.sets) ~= "table" then
        SfuiDB.sets = {}
    end
    local db = SfuiDB.sets
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
    end
    return db
end

local function SafeLower(v)
    if v == nil or issecretvalue(v) then return "" end
    return tostring(v):lower()
end

local function SafeFontPath()
    if common and common.get_font_file then
        return common.get_font_file()
    end
    return "Fonts\\FRIZQT__.TTF"
end

local function GetPlayerClassToken()
    if sfui.talents and sfui.talents.get_player_class then
        local _, _, tok = sfui.talents.get_player_class()
        if type(tok) == "string" and tok ~= "" then
            return tok:upper()
        end
    end
    if _G.UnitClass then
        local _, tok = _G.UnitClass("player")
        if type(tok) == "string" and tok ~= "" then
            return tok:upper()
        end
    end
    return "WARRIOR"
end

local function GetPlayerRole()
    if sfui.gear and sfui.gear.GetClassicRole then
        local r = sfui.gear.GetClassicRole()
        if type(r) == "string" and r ~= "" then
            return r:lower()
        end
    end
    return nil
end

local function GetItemMeta(itemID)
    local name, link, quality, icon
    if common and common.get_item_info then
        name, link, quality, _, _, _, _, _, _, icon = common.get_item_info(itemID)
    elseif GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
    end
    if issecretvalue(name) then name = nil end
    if issecretvalue(link) then link = nil end
    if issecretvalue(quality) then quality = nil end
    if issecretvalue(icon) then icon = nil end

    if not icon then
        if common and common.get_item_instant_info then
            local _, _, _, _, tex = common.get_item_instant_info(itemID)
            if not issecretvalue(tex) then icon = tex end
        elseif C_Item and C_Item.GetItemInfoInstant then
            local _, _, _, _, tex = C_Item.GetItemInfoInstant(itemID)
            if not issecretvalue(tex) then icon = tex end
        end
    end
    if not name and common and common.request_item_load then
        common.request_item_load(itemID)
    elseif not name and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end

    return name and SafeLower(name) or nil, link or ("item:" .. tostring(itemID)), tonumber(quality) or 3, icon or FALLBACK_ICON
end

local function GetQualityRGB(quality)
    if common and common.get_item_quality_color then
        local r, g, b = common.get_item_quality_color(quality or 3)
        if not (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then
            return r, g, b
        end
    end
    if quality == 4 then return 0.64, 0.21, 0.93 end
    if quality == 2 then return 0.12, 1.00, 0.00 end
    if quality == 1 then return 1.00, 1.00, 1.00 end
    return 0.00, 0.44, 0.87
end

local function IsSetWishlisted(itemID)
    return sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted and sfui.dungeonjournal.IsWishlisted(itemID) and true or false
end

local function IsQuestCompleted(questID)
    if not questID then return false end
    if common and common.is_quest_completed then
        return common.is_quest_completed(questID) == true
    end
    if _G.C_QuestLog and _G.C_QuestLog.IsQuestFlaggedCompleted then
        return _G.C_QuestLog.IsQuestFlaggedCompleted(questID) == true
    end
    return false
end

local function GetTSMPriceText(itemID)
    local tsm = _G.TSM_API
    if type(tsm) ~= "table" or type(tsm.GetCustomPriceValue) ~= "function" then
        return nil, nil
    end
    local key = "i:" .. tostring(itemID)
    local copper = tsm.GetCustomPriceValue("dbminbuyout", key)
    if type(copper) ~= "number" or copper <= 0 then
        copper = tsm.GetCustomPriceValue("dbmarket", key)
    end
    if type(copper) ~= "number" or copper <= 0 then
        return nil, nil
    end
    if copper >= 10000 then
        return string_format("%dg", math_floor(copper / 10000 + 0.5)), copper
    elseif copper >= 100 then
        return string_format("%ds", math_floor(copper / 100 + 0.5)), copper
    end
    return string_format("%dc", math_floor(copper + 0.5)), copper
end

-- Scratch equipped item lookup rebuilt once per render pass
local equippedMap = {}
local function RefreshEquippedMap()
    table_wipe(equippedMap)
    if not GetInventoryItemID then return end
    for slot = 1, 19 do
        local eqID = GetInventoryItemID("player", slot)
        if eqID and not issecretvalue(eqID) and type(eqID) == "number" and eqID > 0 then
            equippedMap[eqID] = true
        end
    end
end

local function GetBagCount(itemID)
    if sfui.inventory and sfui.inventory.GetCount then
        local c = sfui.inventory.GetCount(itemID)
        if type(c) == "number" and not issecretvalue(c) then
            return c
        end
    end
    if C_Item and C_Item.GetItemCount then
        local c = C_Item.GetItemCount(itemID, false, false, false, false)
        if type(c) == "number" and not issecretvalue(c) then
            return c
        end
    elseif _G.GetItemCount then
        local c = _G.GetItemCount(itemID, false)
        if type(c) == "number" and not issecretvalue(c) then
            return c
        end
    end
    return 0
end

local function GetLiveBankCount(itemID, bagCount)
    if C_Item and C_Item.GetItemCount then
        local withBank = C_Item.GetItemCount(itemID, true, false, false, false)
        if type(withBank) == "number" and not issecretvalue(withBank) then
            return math_max(0, withBank - (bagCount or 0))
        end
    elseif _G.GetItemCount then
        local withBank = _G.GetItemCount(itemID, true)
        if type(withBank) == "number" and not issecretvalue(withBank) then
            return math_max(0, withBank - (bagCount or 0))
        end
    end
    return 0
end

local function GetPieceOwnership(itemID)
    local isEq = equippedMap[itemID] == true
    local bags = GetBagCount(itemID)
    local bank = GetLiveBankCount(itemID, bags)
    local altSummary = sfui.alts and sfui.alts.GetAccountItemSummary and sfui.alts.GetAccountItemSummary(itemID, true) or nil

    -- When away from the bank frame, pull stored current-character bank count if saved by sfui.alts
    if bank == 0 and sfui.alts and sfui.alts.GetAccountItemSummary and SfuiDB and type(SfuiDB.alts) == "table" then
        local allSum = sfui.alts.GetAccountItemSummary(itemID, false)
        if allSum and allSum.alts then
            local playerName = _G.UnitName and _G.UnitName("player")
            local pLow = playerName and not issecretvalue(playerName) and playerName:lower() or nil
            for _, a in ipairs(allSum.alts) do
                if pLow and a.name and a.name:find(pLow, 1, true) and (a.bank or 0) > 0 then
                    bank = a.bank
                    break
                end
            end
        end
    end

    local status = "missing"
    if isEq then
        status = "equipped"
    elseif bags > 0 then
        status = "bags"
    elseif bank > 0 then
        status = "bank"
    end

    return {
        status     = status,
        owned      = (status ~= "missing"),
        bags       = bags,
        bank       = bank,
        altSummary = altSummary,
    }
end

local function TryGetUpgradePct(itemID)
    if not (sfui.gear and sfui.gear.EvaluateItemUpgrade) then return nil end
    local res = sfui.gear.EvaluateItemUpgrade(itemID)
    if type(res) == "table" and res.isUpgrade and type(res.pctGain) == "number" and res.pctGain >= 0.5 then
        return math_floor(res.pctGain + 0.5)
    end
    return nil
end

-- ─── UI State ─────────────────────────────────────────────────────────────────
local ui = {
    frame         = nil,
    hostFrame     = nil,
    mounted       = false,
    eventsActive  = false,
    catBtns       = {},
    classDrop     = nil,
    wearableBtn   = nil,
    missingBtn    = nil,
    searchBox     = nil,
    searchHolder  = nil,
    filterText    = "",
    runNextBar    = nil,
    runNextLabel  = nil,
    runNextChips  = {},
    listContainer = nil,
    scrollFrame   = nil,
    scrollChild   = nil,
    emptyText     = nil,
    cardPool      = {},
}

local function IsPanelVisible()
    return ui.frame ~= nil and ui.frame.IsVisible and ui.frame:IsVisible() == true
end

function S.IsPanelVisible()
    return IsPanelVisible()
end

local function UpdateFilterVisuals()
    local db = DB()
    for _, def in ipairs({ "all", "t0", "t05", "dungeon" }) do
        local btn = ui.catBtns[def]
        if btn and theme and theme.SetButtonSelected then
            theme.SetButtonSelected(btn, db.category == def)
        end
    end
    if ui.wearableBtn then
        if theme and theme.SetButtonSelected then
            theme.SetButtonSelected(ui.wearableBtn, db.wearableOnly == true)
        end
        ui.wearableBtn:SetAlpha(db.classFilter == "all" and 0.50 or 1.0)
    end
    if ui.missingBtn and theme and theme.SetButtonSelected then
        theme.SetButtonSelected(ui.missingBtn, db.missingOnly == true)
    end
    if ui.classDrop and ui.classDrop.SetSelectedValue then
        ui.classDrop:SetSelectedValue(db.classFilter or "mine")
    end
end

local function ApplySetCardTheme(card)
    local pal = theme and theme.GetPalette and theme.GetPalette()
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(card)
    elseif common and common.apply_flat_backdrop then
        local c = pal and pal.containerColor or { 0.08, 0.08, 0.11, 0.92 }
        local b = pal and pal.borderColor or { 0.22, 0.22, 0.28, 1 }
        common.apply_flat_backdrop(card, c, b)
    end
    if card.divider and pal and pal.borderColor then
        card.divider:SetColorTexture(pal.borderColor[1] or 0.3, pal.borderColor[2] or 0.3, pal.borderColor[3] or 0.35, 0.55)
    end
end

local function StyleTileBorder(tile, own, quality)
    if not tile.icoFrame or not tile.icoFrame.SetBackdropBorderColor then return end
    if own.status == "equipped" then
        tile.icoFrame:SetBackdropBorderColor(0.22, 0.90, 0.45, 1.0)
    elseif own.status == "bags" or own.status == "bank" then
        tile.icoFrame:SetBackdropBorderColor(0.25, 0.80, 1.00, 1.0)
    elseif own.altSummary and (own.altSummary.totalAlts or 0) > 0 then
        tile.icoFrame:SetBackdropBorderColor(0.70, 0.45, 1.00, 0.95)
    else
        local qr, qg, qb = GetQualityRGB(quality)
        tile.icoFrame:SetBackdropBorderColor(qr * 0.55, qg * 0.55, qb * 0.55, 0.70)
    end
end

local function NavigateToPieceSource(set, pieceIdx, itemID)
    local sc = DATA()
    if not (sc and sfui.dungeonjournal) then return end

    if set.category == "t05" then
        local baseSet = set.upgradeFrom and sc.GetSetByID and sc.GetSetByID(set.upgradeFrom)
        local t0ID = baseSet and baseSet.pieces and baseSet.pieces[pieceIdx]
        if t0ID then
            local t0Own = GetPieceOwnership(t0ID)
            if not t0Own.owned then
                local t0Srcs = sc.GetPieceSources(t0ID)
                local first = t0Srcs and t0Srcs[1]
                if first and first.dungeonID then
                    if first.bossName and sfui.dungeonjournal.OpenToBoss then
                        sfui.dungeonjournal.OpenToBoss(first.bossName, first.dungeonID)
                    elseif sfui.dungeonjournal.OpenToDungeon then
                        sfui.dungeonjournal.OpenToDungeon(first.dungeonID, "bosses")
                    end
                    return
                end
            end
        end
        local stage = sc.T05_PIECE_STAGE[pieceIdx] or 1
        local st = sc.T05_STAGES[stage]
        if st and st.dungeon and sfui.dungeonjournal.OpenToDungeon then
            sfui.dungeonjournal.OpenToDungeon(st.dungeon, "quests")
        end
        return
    end

    local srcs = sc.GetPieceSources(itemID)
    local primary = srcs and srcs[1]
    if primary and primary.dungeonID then
        if primary.bossName and sfui.dungeonjournal.OpenToBoss then
            sfui.dungeonjournal.OpenToBoss(primary.bossName, primary.dungeonID)
        elseif sfui.dungeonjournal.OpenToDungeon then
            sfui.dungeonjournal.OpenToDungeon(primary.dungeonID, "bosses")
        end
    end
end

local function ShowPieceTooltip(btn)
    local tip = (common and common.get_tooltip and common.get_tooltip()) or GameTooltip
    if not (tip and btn._itemID) then return end
    local itemID = btn._itemID
    local set = btn._set
    local pieceIdx = btn._pieceIdx or 1
    local own = btn._own or GetPieceOwnership(itemID)
    local sc = DATA()

    tip:SetOwner(btn, "ANCHOR_RIGHT")
    if tip.SetItemByID then
        tip:SetItemByID(itemID)
    elseif tip.SetHyperlink then
        tip:SetHyperlink("item:" .. tostring(itemID))
    end

    tip:AddLine(" ")

    -- Ownership status
    if own.status == "equipped" then
        tip:AddLine("status: equipped", 0.25, 0.92, 0.45)
    elseif own.status == "bags" then
        tip:AddLine(string_format("status: in bags (%d)", own.bags), 0.30, 0.85, 1.00)
    elseif own.status == "bank" then
        tip:AddLine(string_format("status: in bank (%d)", own.bank), 0.30, 0.85, 1.00)
    else
        tip:AddLine("status: missing", 0.85, 0.35, 0.35)
    end

    if own.altSummary and (own.altSummary.totalAlts or 0) > 0 then
        local names = {}
        for i = 1, math_min(3, #own.altSummary.alts) do
            local a = own.altSummary.alts[i]
            names[#names + 1] = string_format("%s (%d)", a.name, a.total)
        end
        tip:AddLine("alts: " .. table_concat(names, ", "), 0.72, 0.55, 1.00)
    end

    -- Sources / T0 -> T0.5 quest stage
    if set and set.category == "t05" and sc then
        local baseSet = set.upgradeFrom and sc.GetSetByID(set.upgradeFrom)
        local t0ID = baseSet and baseSet.pieces and baseSet.pieces[pieceIdx]
        local stage = sc.T05_PIECE_STAGE[pieceIdx] or 1
        local st = sc.T05_STAGES[stage]
        local qID = sc.GetT05QuestID(set.class, stage)
        local qDone = IsQuestCompleted(qID)
        if t0ID then
            local t0Name = GetItemMeta(t0ID) or ("item #" .. tostring(t0ID))
            local t0Own = GetPieceOwnership(t0ID)
            local t0State = t0Own.owned and "|cff33ee77owned|r" or "|cffff6666missing|r"
            tip:AddLine("requires t0: " .. t0Name .. " (" .. t0State .. ")", 0.85, 0.85, 0.95)
            local t0Srcs = sc.GetPieceSources(t0ID)
            if t0Srcs and t0Srcs[1] then
                local s1 = t0Srcs[1]
                tip:AddLine("t0 drops: " .. (s1.displayBoss or "unknown") .. " · " .. (s1.dungeonName or ""), 0.65, 0.75, 0.85)
            end
        end
        if st then
            local doneTag = qDone and " |cff33ee77(completed)|r" or ""
            tip:AddLine(string_format("quest stage %d: %s%s", stage, st.name, doneTag), 0.78, 0.58, 1.00)
        end
    elseif sc then
        local srcs = sc.GetPieceSources(itemID)
        local skipFirstDropLine = (tip._sfuiDJAnnotated == itemID or tip._sfuiSetAnnotated == itemID)
        for i, src in ipairs(srcs) do
            if i <= 4 and not (i == 1 and skipFirstDropLine and not src.dropRate and not src.boe) then
                local prefix = (i == 1) and "drops from: " or "also: "
                local rate = src.dropRate and (" (" .. tostring(src.dropRate) .. "%)") or ""
                local boeTag = src.boe and " [boe]" or ""
                local who = src.displayBoss or "unknown"
                if src.mobs then
                    who = who .. " (" .. src.mobs .. ")"
                end
                local dName = src.dungeonName and (" · " .. src.dungeonName) or ""
                tip:AddLine(prefix .. who .. rate .. boeTag .. dName, 0.92, 0.85, 0.55, true)
            end
        end
        if srcs and srcs[1] and srcs[1].boe then
            local priceTxt = GetTSMPriceText(itemID)
            if priceTxt then
                tip:AddLine("ah buyout (tsm): " .. priceTxt, 1.00, 0.82, 0.20)
            end
        end
    end

    if btn._upgPct then
        tip:AddLine(string_format("estimated upgrade: +%d%%", btn._upgPct), 0.35, 0.95, 0.45)
    end

    tip:AddLine("left-click: open source · right-click: wishlist · shift: link · ctrl: try on", 0.55, 0.55, 0.60, true)
    tip:Show()
end

local function EnsureTileWidget(card, idx)
    if card.tiles[idx] then return card.tiles[idx] end
    local tile = CreateFrame("Button", nil, card)
    tile:SetSize(TILE_W, TILE_H)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icoFrame = CreateFrame("Frame", nil, tile, "BackdropTemplate")
    icoFrame:SetSize(34, 34)
    icoFrame:SetPoint("TOP", tile, "TOP", 0, -1)
    if common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(icoFrame, { 0.04, 0.04, 0.06, 0.95 }, { 0.35, 0.35, 0.40, 0.85 })
    elseif icoFrame.SetBackdrop then
        icoFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        icoFrame:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    end
    tile.icoFrame = icoFrame

    local icon = icoFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", icoFrame, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", icoFrame, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tile.icon = icon

    local hl = icoFrame:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(1, 1, 1, 0.16)

    local wishStar = icoFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    wishStar:SetSize(12, 12)
    wishStar:SetPoint("TOPRIGHT", icoFrame, "TOPRIGHT", 3, 3)
    wishStar:SetTexture(WISHLIST_TEX)
    wishStar:Hide()
    tile.wishStar = wishStar

    local statusBadge = icoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusBadge:SetFont(SafeFontPath(), 10, "OUTLINE")
    statusBadge:SetPoint("TOPLEFT", icoFrame, "TOPLEFT", 1, -1)
    statusBadge:Hide()
    tile.statusBadge = statusBadge

    local line1 = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line1:SetFont(SafeFontPath(), 9, "")
    line1:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -37)
    line1:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -1, -37)
    line1:SetJustifyH("CENTER")
    if line1.SetWordWrap then line1:SetWordWrap(false) end
    tile.line1 = line1

    local line2 = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    line2:SetFont(SafeFontPath(), 8.5, "")
    line2:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -49)
    line2:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -1, -49)
    line2:SetJustifyH("CENTER")
    if line2.SetWordWrap then line2:SetWordWrap(false) end
    tile.line2 = line2

    tile:SetScript("OnEnter", function(self)
        ShowPieceTooltip(self)
    end)
    tile:SetScript("OnLeave", function()
        if common and common.hide_tooltip then
            common.hide_tooltip()
        elseif GameTooltip then
            GameTooltip:Hide()
        end
    end)
    tile:SetScript("OnClick", function(self, button)
        local itemID = self._itemID
        if not itemID then return end
        local _, link = GetItemMeta(itemID)
        if button == "RightButton" then
            if sfui.dungeonjournal and sfui.dungeonjournal.ToggleWishlist then
                sfui.dungeonjournal.ToggleWishlist(itemID)
                if S.Refresh then S.Refresh() end
            end
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if common and common.insert_link_to_chat then
                common.insert_link_to_chat(link)
            end
            return
        end
        if IsControlKeyDown and IsControlKeyDown() then
            if DressUpItemLink then
                DressUpItemLink(link)
            end
            return
        end
        NavigateToPieceSource(self._set, self._pieceIdx, itemID)
    end)

    card.tiles[idx] = tile
    return tile
end

local function EnsureCard(idx)
    if ui.cardPool[idx] then return ui.cardPool[idx] end
    local card = CreateFrame("Frame", nil, ui.scrollChild, "BackdropTemplate")
    card:SetHeight(CARD_H)
    card.tiles = {}

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetFont(SafeFontPath(), 11, "")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -5)
    title:SetPoint("RIGHT", card, "RIGHT", -136, 0)
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end
    card.title = title

    local wishBtn = common.create_flat_button(card, "wishlist", 64, 18)
    wishBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -4)
    wishBtn:SetScript("OnClick", function(self)
        local c = self._card
        local ids = c and c._missingIDs
        if ids and #ids > 0 and sfui.dungeonjournal and sfui.dungeonjournal.AddWishlistItemsBatch then
            sfui.dungeonjournal.AddWishlistItemsBatch(ids, false)
            if S.Refresh then S.Refresh() end
        end
    end)
    card.wishBtn = wishBtn

    local tryBtn = common.create_flat_button(card, "try on", 50, 18)
    tryBtn:SetPoint("RIGHT", wishBtn, "LEFT", -4, 0)
    tryBtn:SetScript("OnClick", function(self)
        local c = self._card
        local s = c and c._set
        if s and s.pieces and DressUpItemLink then
            for _, itemID in ipairs(s.pieces) do
                DressUpItemLink("item:" .. tostring(itemID))
            end
        end
    end)
    card.tryBtn = tryBtn

    wishBtn._card = card
    tryBtn._card = card

    local divider = card:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -25)
    divider:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -25)
    divider:SetColorTexture(0.28, 0.28, 0.34, 0.55)
    card.divider = divider

    ApplySetCardTheme(card)
    ui.cardPool[idx] = card
    return card
end

local function SetMatchesSearch(set, q)
    if not q or q == "" then return true end
    if SafeLower(set.name):find(q, 1, true) then return true end
    if SafeLower(set.armor):find(q, 1, true) then return true end
    if set.class and SafeLower(set.class):find(q, 1, true) then return true end
    if set.role and SafeLower(set.role):find(q, 1, true) then return true end

    local sc = DATA()
    if set.dungeonID and sc and SafeLower(sc.GetDungeonDisplayName(set.dungeonID, false)):find(q, 1, true) then
        return true
    end
    for _, itemID in ipairs(set.pieces or {}) do
        local name = GetItemMeta(itemID)
        if name and name:find(q, 1, true) then
            return true
        end
        if sc then
            for _, src in ipairs(sc.GetPieceSources(itemID)) do
                if (src.displayBoss and src.displayBoss:find(q, 1, true))
                    or (src.dungeonName and src.dungeonName:find(q, 1, true))
                    or (src.mobs and src.mobs:find(q, 1, true)) then
                    return true
                end
            end
        end
    end
    return false
end

local function FormatTileLines(set, pieceIdx, itemID, own, upgPct)
    local sc = DATA()
    local slotName = (set.slots and set.slots[pieceIdx]) or "slot"
    local line1Right = ""
    local line2Text = ""

    if set.category == "t05" and sc then
        local stage = sc.T05_PIECE_STAGE[pieceIdx] or 1
        local qID = sc.GetT05QuestID(set.class, stage)
        local qDone = IsQuestCompleted(qID)
        line1Right = "q" .. tostring(stage) .. (qDone and "✓" or "")
        local baseSet = set.upgradeFrom and sc.GetSetByID(set.upgradeFrom)
        local t0ID = baseSet and baseSet.pieces and baseSet.pieces[pieceIdx]
        local t0Own = t0ID and GetPieceOwnership(t0ID)
        if t0Own and not t0Own.owned then
            local t0Srcs = sc.GetPieceSources(t0ID)
            local s1 = t0Srcs and t0Srcs[1]
            if s1 then
                local who = (s1.trash and "trash") or (common and common.shorten_name and common.shorten_name(s1.displayBoss, 10)) or s1.displayBoss
                local dShort = sc.GetDungeonDisplayName(s1.dungeonID, true)
                line2Text = "|cffcc7777t0:" .. SafeLower(who) .. "·" .. SafeLower(dShort) .. "|r"
            else
                line2Text = "|cffcc7777needs t0|r"
            end
        else
            local st = sc.T05_STAGES[stage]
            local dShort = st and sc.GetDungeonDisplayName(st.dungeon, true) or "quest"
            line2Text = "|cff77ddaa" .. SafeLower(dShort) .. "|r"
        end
    elseif sc then
        local srcs = sc.GetPieceSources(itemID)
        local s1 = srcs and srcs[1]
        if s1 and not own.owned then
            if s1.boe then
                local priceTxt = GetTSMPriceText(itemID)
                line1Right = priceTxt or "boe"
            elseif s1.dropRate then
                line1Right = tostring(s1.dropRate) .. "%"
            elseif upgPct then
                line1Right = "+" .. tostring(upgPct) .. "%"
            end
        end
        if s1 then
            local dShort = s1.dungeonID and sc.GetDungeonDisplayName(s1.dungeonID, true) or nil
            if s1.trash then
                line2Text = dShort and (dShort .. " trash") or SafeLower(s1.displayBoss)
            elseif s1.displayBoss and dShort then
                local shortBoss = (common and common.shorten_name and common.shorten_name(s1.displayBoss, 11)) or s1.displayBoss
                line2Text = SafeLower(shortBoss) .. "·" .. SafeLower(dShort)
            else
                line2Text = SafeLower(s1.displayBoss or dShort or "")
            end
        end
    end

    if own.owned then
        local statusColor = (own.status == "equipped") and "|cff44ee77" or "|cff44ccff"
        return statusColor .. slotName .. "|r", "|cff8899aa" .. SafeLower(line2Text) .. "|r"
    elseif line1Right ~= "" then
        return slotName .. " · |cffffd166" .. line1Right .. "|r", "|cff8899aa" .. SafeLower(line2Text) .. "|r"
    end
    return slotName, "|cff8899aa" .. SafeLower(line2Text) .. "|r"
end

local function RenderRunNextBar(filteredSets)
    if not ui.runNextBar then return end
    local sc = DATA()
    local counts = {}
    local details = {}
    local seenKeys = {}

    for _, chip in ipairs(ui.runNextChips) do
        chip:Hide()
    end

    local function RecordMissing(dungeonID, itemID, srcLabel)
        if not dungeonID or not itemID then return end
        local dKey = dungeonID .. ":" .. tostring(itemID)
        if seenKeys[dKey] then return end
        seenKeys[dKey] = true
        counts[dungeonID] = (counts[dungeonID] or 0) + 1
        local arr = details[dungeonID]
        if not arr then
            arr = {}
            details[dungeonID] = arr
        end
        arr[#arr + 1] = { itemID = itemID, label = srcLabel or "" }
    end

    for _, set in ipairs(filteredSets) do
        for idx, itemID in ipairs(set.pieces or {}) do
            local own = GetPieceOwnership(itemID)
            if not own.owned then
                if set.category == "t05" and sc then
                    local baseSet = set.upgradeFrom and sc.GetSetByID(set.upgradeFrom)
                    local t0ID = baseSet and baseSet.pieces and baseSet.pieces[idx]
                    local t0Own = t0ID and GetPieceOwnership(t0ID)
                    if t0ID and t0Own and not t0Own.owned then
                        local srcs = sc.GetPieceSources(t0ID)
                        local s1 = srcs and srcs[1]
                        if s1 and s1.dungeonID then
                            RecordMissing(s1.dungeonID, t0ID, (s1.displayBoss or "drop") .. " (t0)")
                        end
                    else
                        local stage = sc.T05_PIECE_STAGE[idx] or 1
                        local st = sc.T05_STAGES[stage]
                        if st and st.dungeon then
                            RecordMissing(st.dungeon, itemID, st.name)
                        end
                    end
                elseif sc then
                    local srcs = sc.GetPieceSources(itemID)
                    local s1 = srcs and srcs[1]
                    if s1 and s1.dungeonID then
                        RecordMissing(s1.dungeonID, itemID, s1.displayBoss)
                    end
                end
            end
        end
    end

    local ranked = {}
    for dID, cnt in pairs(counts) do
        ranked[#ranked + 1] = { dungeonID = dID, count = cnt }
    end
    table_sort(ranked, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.dungeonID < b.dungeonID
    end)

    if #ranked == 0 then
        ui.runNextLabel:SetText("run next:  |cff44dd88all visible sets complete|r")
        return
    end

    ui.runNextLabel:SetText("run next:")
    local prevAnchor = ui.runNextLabel
    for i = 1, math_min(MAX_RUN_NEXT_CHIPS, #ranked) do
        local r = ranked[i]
        local chip = ui.runNextChips[i]
        if not chip then
            chip = common.create_flat_button(ui.runNextBar, "", 90, 18)
            chip:SetScript("OnClick", function(self)
                if self._dungeonID and sfui.dungeonjournal and sfui.dungeonjournal.OpenToDungeon then
                    sfui.dungeonjournal.OpenToDungeon(self._dungeonID, "bosses")
                end
            end)
            chip:SetScript("OnEnter", function(self)
                local tip = (common and common.get_tooltip and common.get_tooltip()) or GameTooltip
                if not (tip and self._dungeonID) then return end
                tip:SetOwner(self, "ANCHOR_BOTTOM")
                tip:SetText((sc and sc.GetDungeonDisplayName(self._dungeonID, false) or self._dungeonID) .. " — missing pieces", 1, 0.82, 0.2)
                for _, entry in ipairs(self._details or {}) do
                    local iName = GetItemMeta(entry.itemID) or ("item #" .. tostring(entry.itemID))
                    tip:AddLine("  • " .. iName .. " (" .. SafeLower(entry.label) .. ")", 0.92, 0.92, 0.95)
                end
                tip:AddLine("click to open dungeon bosses", 0.45, 0.95, 0.55)
                tip:Show()
            end)
            chip:SetScript("OnLeave", function()
                if common and common.hide_tooltip then common.hide_tooltip() elseif GameTooltip then GameTooltip:Hide() end
            end)
            ui.runNextChips[i] = chip
        end

        local dShort = (sc and sc.GetDungeonDisplayName(r.dungeonID, true)) or r.dungeonID
        local label = string_format("%s (%d)", dShort, r.count)
        chip:SetText(label)
        local fs = chip.GetFontString and chip:GetFontString()
        local tw = (fs and fs.GetStringWidth and fs:GetStringWidth()) or (#label * 6)
        chip:SetWidth(math_max(54, math_floor(tw + 14)))
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", prevAnchor, "RIGHT", prevAnchor == ui.runNextLabel and 8 or 5, 0)
        chip._dungeonID = r.dungeonID
        chip._details = details[r.dungeonID]
        if theme and theme.ApplyButtonStyle then
            theme.ApplyButtonStyle(chip, false)
        end
        chip:Show()
        prevAnchor = chip
    end
end

local function ComputeFilteredSets()
    local sc = DATA()
    if not sc then return {} end

    local db = DB()
    local playerClass = GetPlayerClassToken()
    local playerRole = GetPlayerRole()
    local targetClass = (db.classFilter == "mine") and playerClass or ((db.classFilter ~= "all") and db.classFilter or nil)
    local q = SafeLower(ui.filterText):gsub("^%s*(.-)%s*$", "%1")
    local list = {}

    for _, s in ipairs(sc.GetAllSets()) do
        local catOK = (db.category == "all") or (s.category == db.category)
        local classOK = true
        if targetClass then
            if s.class then
                classOK = (s.class == targetClass)
            elseif db.wearableOnly then
                classOK = sc.CanClassWearSet(s, targetClass)
            end
        end

        if catOK and classOK and SetMatchesSearch(s, q) then
            local ownedCount = 0
            local missingIDs = {}
            for _, itemID in ipairs(s.pieces or {}) do
                local own = GetPieceOwnership(itemID)
                if own.owned then
                    ownedCount = ownedCount + 1
                else
                    missingIDs[#missingIDs + 1] = itemID
                end
            end
            if not (db.missingOnly and #missingIDs == 0) then
                list[#list + 1] = {
                    set        = s,
                    ownedCount = ownedCount,
                    missingIDs = missingIDs,
                    isOwnClass = (s.class == playerClass),
                }
            end
        end
    end

    table_sort(list, function(a, b)
        if a.isOwnClass ~= b.isOwnClass then return a.isOwnClass end
        local ca, cb = CAT_ORDER[a.set.category] or 9, CAT_ORDER[b.set.category] or 9
        if ca ~= cb then return ca < cb end
        if (a.set.class or "") ~= (b.set.class or "") then
            return (a.set.class or "") < (b.set.class or "")
        end
        if playerRole and a.set.class == b.set.class and a.set.role ~= b.set.role then
            if a.set.role == playerRole then return true end
            if b.set.role == playerRole then return false end
            return (ROLE_ORDER[a.set.role] or 9) < (ROLE_ORDER[b.set.role] or 9)
        end
        local ma, mb = a.set.minLevel or 0, b.set.minLevel or 0
        if ma ~= mb then return ma < mb end
        return (a.set.name or "") < (b.set.name or "")
    end)

    return list
end

function S.Refresh()
    if not ui.frame or not ui.scrollChild then return end
    UpdateFilterVisuals()
    RefreshEquippedMap()

    local entries = ComputeFilteredSets()
    local rawSets = {}
    for i, e in ipairs(entries) do rawSets[i] = e.set end
    RenderRunNextBar(rawSets)

    local cardWidth = math_max(720, ((ui.scrollFrame and ui.scrollFrame.GetWidth and ui.scrollFrame:GetWidth()) or (PANEL_W - 28)) - 4)
    local sc = DATA()

    for i = 1, #entries do
        local entry = entries[i]
        local s = entry.set
        local card = EnsureCard(i)
        card:ClearAllPoints()
        card:SetWidth(cardWidth)
        card:SetPoint("TOPLEFT", ui.scrollChild, "TOPLEFT", 0, -((i - 1) * (CARD_H + CARD_GAP)))
        card._set = s
        card._missingIDs = entry.missingIDs

        local tagText = s.isForever and (s.category == "t05" and "[t0.5 · forever]" or "[forever]")
            or (s.category == "t0" and "[t0]" or "[dungeon]")
        local nameDisplay = SafeLower(s.name)
        if s.class and colors and colors.class_color_name then
            nameDisplay = colors.class_color_name(nameDisplay, s.class)
        else
            nameDisplay = "|cffffd100" .. nameDisplay .. "|r"
        end
        local roleStr = s.role and ("  |cff99bbff[" .. SafeLower(s.role) .. "]|r") or ""
        local lvlStr = string_format("  |cff888899%s · lvl %d-%d|r", SafeLower(s.armor), s.minLevel or 1, s.maxLevel or 60)
        local totalPieces = #(s.pieces or {})
        local countColor = (entry.ownedCount >= totalPieces) and "|cff44ee77" or "|cffdddddd"
        local progStr = string_format("  %s%d/%d|r", countColor, entry.ownedCount, totalPieces)
        local dLabel = s.dungeonID and sc and ("  |cff778899· " .. SafeLower(sc.GetDungeonDisplayName(s.dungeonID, false)) .. "|r") or ""

        card.title:SetText(string_format("|cff88aacc%s|r  %s%s%s%s%s", tagText, nameDisplay, roleStr, lvlStr, progStr, dLabel))

        if #entry.missingIDs == 0 then
            card.wishBtn:Hide()
        else
            local allWished = true
            for _, id in ipairs(entry.missingIDs) do
                if not IsSetWishlisted(id) then
                    allWished = false
                    break
                end
            end
            card.wishBtn:SetText(allWished and "wishlisted" or "wishlist")
            if theme and theme.SetButtonSelected then
                theme.SetButtonSelected(card.wishBtn, allWished)
            end
            card.wishBtn:Show()
        end

        local pieces = s.pieces or {}
        for tIdx = 1, 8 do
            local itemID = pieces[tIdx]
            if itemID then
                local tile = EnsureTileWidget(card, tIdx)
                local own = GetPieceOwnership(itemID)
                local _, _, quality, iconTex = GetItemMeta(itemID)
                local upgPct = (not own.owned) and TryGetUpgradePct(itemID) or nil

                tile:ClearAllPoints()
                tile:SetPoint("TOPLEFT", card, "TOPLEFT", 8 + (tIdx - 1) * (TILE_W + TILE_GAP), -29)
                tile._itemID = itemID
                tile._set = s
                tile._pieceIdx = tIdx
                tile._own = own
                tile._upgPct = upgPct

                tile.icon:SetTexture(iconTex)
                tile.icon:SetAlpha(own.owned and 1.0 or 0.58)
                StyleTileBorder(tile, own, quality)

                if IsSetWishlisted(itemID) then
                    tile.wishStar:Show()
                else
                    tile.wishStar:Hide()
                end

                if own.status == "equipped" then
                    tile.statusBadge:SetText("|cff44ee77e|r")
                    tile.statusBadge:Show()
                elseif own.status == "bags" or own.status == "bank" then
                    tile.statusBadge:SetText("|cff44ccffb|r")
                    tile.statusBadge:Show()
                elseif own.altSummary and (own.altSummary.totalAlts or 0) > 0 then
                    tile.statusBadge:SetText("|cffb077ffa|r")
                    tile.statusBadge:Show()
                else
                    tile.statusBadge:Hide()
                end

                local l1, l2 = FormatTileLines(s, tIdx, itemID, own, upgPct)
                tile.line1:SetText(l1)
                tile.line2:SetText(l2)
                tile:Show()
            elseif card.tiles[tIdx] then
                card.tiles[tIdx]:Hide()
            end
        end

        ApplySetCardTheme(card)
        card:Show()
    end

    for i = #entries + 1, #ui.cardPool do
        ui.cardPool[i]:Hide()
    end

    local totalH = math_max(1, #entries * (CARD_H + CARD_GAP))
    ui.scrollChild:SetSize(cardWidth, totalH)
    if ui.emptyText then
        ui.emptyText:SetShown(#entries == 0)
    end
end

local function ScheduleRefresh()
    if not IsPanelVisible() then return end
    if common and common.debounce then
        common.debounce("sets_panel_refresh", 0.08, function()
            if IsPanelVisible() then
                S.Refresh()
            end
        end)
    else
        S.Refresh()
    end
end

local function OnPanelEvent(event, arg1)
    if not IsPanelVisible() then return end
    if event == "GET_ITEM_INFO_RECEIVED" then
        if issecretvalue(arg1) or type(arg1) ~= "number" then return end
        local sc = DATA()
        if not (sc and sc.GetItemSetInfo and sc.GetItemSetInfo(arg1)) then return end
    end
    ScheduleRefresh()
end

local function RegisterPanelEvents()
    if ui.eventsActive or not sfui.events then return end
    ui.eventsActive = true
    if sfui.events.RegisterDebouncedEvent then
        sfui.events.RegisterDebouncedEvent("GET_ITEM_INFO_RECEIVED", 0.15, OnPanelEvent)
        sfui.events.RegisterDebouncedEvent("BAG_UPDATE_DELAYED", 0.15, OnPanelEvent)
        sfui.events.RegisterDebouncedEvent("PLAYER_EQUIPMENT_CHANGED", 0.10, OnPanelEvent)
        sfui.events.RegisterDebouncedEvent("BANKFRAME_OPENED", 0.15, OnPanelEvent)
        sfui.events.RegisterDebouncedEvent("QUEST_TURNED_IN", 0.15, OnPanelEvent)
    end
end

local function UnregisterPanelEvents()
    if not ui.eventsActive or not sfui.events or not sfui.events.UnregisterEvent then return end
    ui.eventsActive = false
    sfui.events.UnregisterEvent("GET_ITEM_INFO_RECEIVED", OnPanelEvent)
    sfui.events.UnregisterEvent("BAG_UPDATE_DELAYED", OnPanelEvent)
    sfui.events.UnregisterEvent("PLAYER_EQUIPMENT_CHANGED", OnPanelEvent)
    sfui.events.UnregisterEvent("BANKFRAME_OPENED", OnPanelEvent)
    sfui.events.UnregisterEvent("QUEST_TURNED_IN", OnPanelEvent)
end

local function BuildPanelContents(container)
    if ui.filterBar then return end
    local db = DB()
    local baseLevel = (container.GetFrameLevel and container:GetFrameLevel()) or 1
    local sc = DATA()

    -- 1. Filter Bar
    local filterBar = CreateFrame("Frame", nil, container)
    filterBar:SetPoint("TOPLEFT", container, "TOPLEFT", 2, -2)
    filterBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -2, -2)
    filterBar:SetHeight(26)
    filterBar:SetFrameLevel(baseLevel + 5)
    ui.filterBar = filterBar

    local catDefs = {
        { id = "all",     label = "all",     w = 36 },
        { id = "t0",      label = "t0",      w = 34 },
        { id = "t05",     label = "t0.5",    w = 42 },
        { id = "dungeon", label = "dungeon", w = 64 },
    }
    local prevBtn = nil
    for _, cDef in ipairs(catDefs) do
        local btn = common.create_flat_button(filterBar, cDef.label, cDef.w, 20)
        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", filterBar, "LEFT", 2, 0)
        end
        btn:SetScript("OnClick", function()
            DB().category = cDef.id
            S.Refresh()
        end)
        ui.catBtns[cDef.id] = btn
        prevBtn = btn
    end

    local classOptions = {
        { text = "my class",    value = "mine" },
        { text = "all classes", value = "all" },
    }
    for _, cls in ipairs((sc and sc.CLASS_ORDER) or {}) do
        classOptions[#classOptions + 1] = { text = SafeLower(cls), value = cls }
    end

    local classDrop = common.create_dropdown(filterBar, 104, classOptions, function(val)
        DB().classFilter = val
        S.Refresh()
    end, db.classFilter or "mine", nil, 132)
    classDrop:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
    ui.classDrop = classDrop

    local wearableBtn = common.create_flat_button(filterBar, "wearable", 64, 20)
    wearableBtn:SetPoint("LEFT", classDrop, "RIGHT", 6, 0)
    wearableBtn:SetScript("OnClick", function()
        local d = DB()
        d.wearableOnly = not d.wearableOnly
        S.Refresh()
    end)
    wearableBtn.tooltip = "hide dungeon armor sets your class cannot equip"
    ui.wearableBtn = wearableBtn

    local missingBtn = common.create_flat_button(filterBar, "missing", 58, 20)
    missingBtn:SetPoint("LEFT", wearableBtn, "RIGHT", 4, 0)
    missingBtn:SetScript("OnClick", function()
        local d = DB()
        d.missingOnly = not d.missingOnly
        S.Refresh()
    end)
    missingBtn.tooltip = "show only incomplete sets"
    ui.missingBtn = missingBtn

    local searchBox = CreateFrame("EditBox", nil, filterBar, "BackdropTemplate")
    searchBox:SetSize(164, 20)
    searchBox:SetPoint("RIGHT", filterBar, "RIGHT", -2, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    if searchBox.SetTextInsets then searchBox:SetTextInsets(6, 6, 0, 0) end
    if theme and theme.ApplyInputStyle then
        theme.ApplyInputStyle(searchBox)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(searchBox, { 0.05, 0.05, 0.07, 0.9 }, { 0.22, 0.22, 0.28, 1 })
    end
    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    placeholder:SetText("search sets...")
    ui.searchHolder = placeholder
    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText() or ""
        ui.filterText = txt
        placeholder:SetShown(txt == "")
        ScheduleRefresh()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then
            self:SetText("")
        end
        self:ClearFocus()
    end)
    ui.searchBox = searchBox

    -- 2. "run next" Farm Planner Bar
    local runNextBar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    runNextBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
    runNextBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -4)
    runNextBar:SetHeight(24)
    runNextBar:SetFrameLevel(baseLevel + 4)
    if theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(runNextBar)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(runNextBar, { 0.06, 0.06, 0.08, 0.85 }, { 0.2, 0.2, 0.25, 0.8 })
    end
    ui.runNextBar = runNextBar

    local runLabel = runNextBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    runLabel:SetFont(SafeFontPath(), 10, "")
    runLabel:SetPoint("LEFT", runNextBar, "LEFT", 8, 0)
    runLabel:SetTextColor(0.85, 0.80, 0.55)
    runLabel:SetText("run next:")
    ui.runNextLabel = runLabel

    -- 3. Scrollable Cards List
    local listContainer = CreateFrame("Frame", nil, container, "BackdropTemplate")
    listContainer:SetPoint("TOPLEFT", runNextBar, "BOTTOMLEFT", 0, -4)
    listContainer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 2)
    listContainer:SetFrameLevel(baseLevel + 2)
    if theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(listContainer)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(listContainer, { 0.04, 0.04, 0.05, 0.85 }, { 0.18, 0.18, 0.22, 0.8 })
    end
    ui.listContainer = listContainer

    local sf = CreateFrame("ScrollFrame", "SfuiSetsScrollFrame", listContainer, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", listContainer, "BOTTOMRIGHT", -24, 4)
    local sb = sf.ScrollBar
    if sb then
        if theme and theme.ApplyScrollBarStyle then
            theme.ApplyScrollBarStyle(sb)
        elseif common and common.style_scrollbar then
            common.style_scrollbar(sb)
        end
    end
    ui.scrollFrame = sf

    local scrollChild = CreateFrame("Frame", nil, sf)
    scrollChild:SetSize(PANEL_W - 36, 1)
    sf:SetScrollChild(scrollChild)
    ui.scrollChild = scrollChild

    local emptyText = listContainer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("CENTER", listContainer, "CENTER", 0, 0)
    emptyText:SetText("no sets match current filters")
    emptyText:Hide()
    ui.emptyText = emptyText
end

function S.MountPanel(parentContainer, hostWindow)
    if not parentContainer then return nil end
    if ui.mounted and ui.frame == parentContainer then
        ui.hostFrame = hostWindow or ui.hostFrame
        return ui.frame
    end
    ui.frame = parentContainer
    ui.hostFrame = hostWindow or (parentContainer.GetParent and parentContainer:GetParent()) or parentContainer
    ui.mounted = true
    S.frame = ui.frame

    BuildPanelContents(parentContainer)
    parentContainer:SetScript("OnShow", function()
        S.OnPanelShown()
    end)
    parentContainer:HookScript("OnHide", UnregisterPanelEvents)
    return ui.frame
end

function S.OnPanelShown()
    RegisterPanelEvents()
    S.Refresh()
end

function S.ApplyTheme()
    if ui.runNextBar and theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(ui.runNextBar)
    end
    if ui.listContainer and theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(ui.listContainer)
    end
    if ui.searchBox and theme and theme.ApplyInputStyle then
        theme.ApplyInputStyle(ui.searchBox)
    end
    if IsPanelVisible() then
        S.Refresh()
    end
end

function S.ApplyFilterArg(arg)
    if type(arg) ~= "string" or arg == "" then return end
    local low = SafeLower(arg):gsub("^%s*(.-)%s*$", "%1")
    local db = DB()
    if low == "t0" or low == "t0.5" or low == "t05" or low == "dungeon" or low == "all" then
        db.category = (low == "t0.5") and "t05" or low
    elseif low == "scarlet" or low == "defias" or low == "gladiator" or low == "ironweave" then
        db.category = "dungeon"
        db.classFilter = "all"
        ui.filterText = low
        if ui.searchBox then ui.searchBox:SetText(low) end
    else
        ui.filterText = low
        if ui.searchBox then ui.searchBox:SetText(low) end
    end
end

function S.Open(arg)
    S.ApplyFilterArg(arg)
    if sfui.dungeonjournal and sfui.dungeonjournal.OpenTab then
        sfui.dungeonjournal.OpenTab("sets")
        if IsPanelVisible() then
            S.Refresh()
        end
    end
end

function S.Close()
    if ui.hostFrame and IsPanelVisible() and sfui.dungeonjournal and sfui.dungeonjournal.Close then
        sfui.dungeonjournal.Close()
    end
end

function S.Toggle(arg)
    if IsPanelVisible() and (not arg or arg == "") then
        S.Close()
    else
        S.Open(arg)
    end
end

function S.FocusSet(idOrSetID)
    local sc = DATA()
    local s = sc and sc.GetSetByID and sc.GetSetByID(idOrSetID)
    if not s then return false end
    local db = DB()
    db.category = s.category or "all"
    if s.class then
        db.classFilter = s.class
    else
        db.classFilter = "all"
    end
    db.missingOnly = false
    ui.filterText = SafeLower(s.name)
    if ui.searchBox then ui.searchBox:SetText(ui.filterText) end
    S.Open()
    return true
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", function()
        if IsPanelVisible() then ScheduleRefresh() end
    end)
    sfui.events.RegisterMessage("SFUI_GEAR_ROLE_CHANGED", function()
        if IsPanelVisible() then ScheduleRefresh() end
    end)
end

S._internals = {
    GetPieceOwnership = GetPieceOwnership,
    GetTSMPriceText   = GetTSMPriceText,
    ComputeFilteredSets = ComputeFilteredSets,
    RenderRunNextBar  = RenderRunNextBar,
    ui                = ui,
}
