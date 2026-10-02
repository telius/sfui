local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_bosses.lua
--  Boss selection list + loot scroll panel for the Camelot Dungeon Journal.
--  Uses frame pooling for boss list buttons and loot row items.
--  Resolves items lazily via sfui.common.get_item_info() and handles
--  ITEM_DATA_LOAD_RESULT with debounced UI refreshes.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

-- ─── Constants ────────────────────────────────────────────────────────────────
local BOSS_BTN_H    = 42
local BOSS_BTN_PAD  = 4
local LOOT_ROW_H    = 44
local LOOT_ROW_PAD  = 4
local ICON_SZ       = 34
local BOSS_LIST_W   = 200

local theme  = sfui.theme
local common = sfui.common

-- ─── Locals & State ───────────────────────────────────────────────────────────
local bossPanel         = nil
local bossListScroll    = nil
local bossListContent   = nil
local lootScroll        = nil
local lootContent       = nil
local bossHeaderFrame   = nil

local bossButtons       = {}
local lootButtons       = {}

local selectedBossIndex = 1
local debounceTimer     = nil
local currentBossItemSet = {}
local currentLootFilter = "all"
local filterButtons     = {}

local FILTER_BUTTONS = {
    { key = "all",      label = "All" },
    { key = "armor",    label = "Armor" },
    { key = "weapons",  label = "Weapons" },
    { key = "trinkets", label = "Trinkets" },
    { key = "wishlist", label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t Wishlist" },
}

local function IsItemMatchingFilter(filterKey, itemID, classID, subclassID, equipSlot, itemLink)
    if filterKey == "all" then
        return true
    elseif filterKey == "wishlist" then
        local dj = sfui.dungeonjournal
        return dj and dj.IsWishlisted and dj.IsWishlisted(itemID)
    elseif filterKey == "armor" then
        local isArmor = (classID == 4 and equipSlot ~= "INVTYPE_TRINKET" and equipSlot ~= "INVTYPE_FINGER" and equipSlot ~= "INVTYPE_NECK" and equipSlot ~= "INVTYPE_HOLDABLE")
            or equipSlot == "INVTYPE_HEAD"
            or equipSlot == "INVTYPE_SHOULDER"
            or equipSlot == "INVTYPE_CHEST"
            or equipSlot == "INVTYPE_ROBE"
            or equipSlot == "INVTYPE_WAIST"
            or equipSlot == "INVTYPE_LEGS"
            or equipSlot == "INVTYPE_FEET"
            or equipSlot == "INVTYPE_WRIST"
            or equipSlot == "INVTYPE_HAND"
            or equipSlot == "INVTYPE_CLOAK"
            or equipSlot == "INVTYPE_SHIELD"
        return isArmor == true
    elseif filterKey == "weapons" then
        local isWeapon = (classID == 2)
            or equipSlot == "INVTYPE_WEAPON"
            or equipSlot == "INVTYPE_2HWEAPON"
            or equipSlot == "INVTYPE_WEAPONMAINHAND"
            or equipSlot == "INVTYPE_WEAPONOFFHAND"
            or equipSlot == "INVTYPE_RANGED"
            or equipSlot == "INVTYPE_RANGEDRIGHT"
            or equipSlot == "INVTYPE_THROWN"
        return isWeapon == true
    elseif filterKey == "trinkets" then
        local isTrinket = equipSlot == "INVTYPE_TRINKET"
            or equipSlot == "INVTYPE_FINGER"
            or equipSlot == "INVTYPE_NECK"
            or equipSlot == "INVTYPE_HOLDABLE"
        return isTrinket == true
    end
    return true
end

-- ─── Database & State Access ──────────────────────────────────────────────────
local function DJ_DB()
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    return SfuiDB.dungeonjournal
end

local function GetCurrentDungeon()
    local dj = sfui.dungeonjournal
    if not dj then return nil end
    local id = dj.GetSelectedDungeonID and dj.GetSelectedDungeonID()
    local helpers = dj.GetItemHelpers and dj.GetItemHelpers()
    if helpers and helpers.FindDungeon then
        if id then
            return helpers.FindDungeon(id)
        end
        -- Default to the first dungeon in the current tab list if none selected
        local list = helpers.GetList and helpers.GetList()
        if list and #list > 0 then
            return list[1]
        end
    end
    return nil
end

local function GetEncounterList(dungeon)
    if not dungeon then return {} end
    local bosses = dungeon.bosses or {}
    if #bosses == 0 then return {} end

    -- Build All Bosses combined entry
    local allItems = {}
    local seenItems = {}
    local allDropRates = {}
    for _, b in ipairs(bosses) do
        for _, it in ipairs(b.items or {}) do
            local id = type(it) == "table" and (it.id or it[1]) or it
            id = tonumber(id)
            if id and not seenItems[id] then
                seenItems[id] = true
                allItems[#allItems + 1] = it
            end
            if id and b.dropRates and b.dropRates[id] and not allDropRates[id] then
                allDropRates[id] = b.dropRates[id]
            end
        end
    end

    local list = {}
    list[1] = {
        isAll       = true,
        name        = "All Bosses",
        level       = "All",
        subtitle    = string.format("%d encounters · %d drops", #bosses, #allItems),
        icon        = dungeon.icon or 133743,
        items       = allItems,
        dropRates   = allDropRates,
    }

    for _, b in ipairs(bosses) do
        list[#list + 1] = b
    end

    return list
end

-- ─── Quality Color Helper ─────────────────────────────────────────────────────
local function GetQualityColor(quality)
    if common and common.get_item_quality_color then
        local r, g, b = common.get_item_quality_color(quality)
        return r, g, b
    end
    local q = quality or 1
    if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q] then
        local c = _G.ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
    if _G.GetItemQualityColor then
        local r, g, b = _G.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end

-- ─── Boss Button Pool ─────────────────────────────────────────────────────────
local function AcquireBossButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then return btn end
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BOSS_BTN_H)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    -- Icon (creature portrait or skull in 1px bordered frame)
    local icoFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.icoFrame = icoFrame
    icoFrame:SetSize(30, 30)
    icoFrame:SetPoint("LEFT", 6, 0)
    icoFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    icoFrame:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    icoFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)

    local ico = icoFrame:CreateTexture(nil, "ARTWORK")
    btn.icon = ico
    ico:SetAllPoints()
    ico:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    -- Name
    local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText = name
    name:SetPoint("TOPLEFT", icoFrame, "TOPRIGHT", 8, -4)
    name:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -4)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    -- Level badge / subtitle
    local levelText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.levelText = levelText
    levelText:SetPoint("BOTTOMLEFT", icoFrame, "BOTTOMRIGHT", 8, 5)
    levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 5)
    levelText:SetJustifyH("LEFT")
    levelText:SetWordWrap(false)
    levelText:SetTextColor(0.65, 0.65, 0.65, 1)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.25)

    pool[#pool + 1] = btn
    return btn
end

-- ─── Loot Button Pool ─────────────────────────────────────────────────────────
local function AcquireLootButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then return btn end
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetHeight(LOOT_ROW_H)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.06, 0.06, 0.08, 0.7)
    btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.8)

    -- Item icon container
    local iconBtn = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.iconBtn = iconBtn
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetPoint("LEFT", 6, 0)
    iconBtn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    btn.iconTex = iconTex
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Wishlist diamond button on the far right
    local starBtn = CreateFrame("Button", nil, btn)
    btn.starBtn = starBtn
    starBtn:SetSize(22, 22)
    starBtn:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

    local starIcon = starBtn:CreateTexture(nil, "ARTWORK")
    starBtn.starIcon = starIcon
    starIcon:SetSize(16, 16)
    starIcon:SetPoint("CENTER", 0, 0)
    starIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
    starIcon:SetDesaturated(true)
    starIcon:SetAlpha(0.25)

    starBtn:SetScript("OnEnter", function(self)
        local isWish = self.isWishlisted
        if not isWish and self.starIcon then
            self.starIcon:SetAlpha(0.7)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if isWish then
            GameTooltip:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffWishlisted Item|r")
            GameTooltip:AddLine("Click to remove from your loot wishlist.", 0.85, 0.85, 0.85)
            GameTooltip:AddLine("Wishlisted items trigger special alert banners and sounds when dropped.", 0.6, 0.6, 0.6, true)
        else
            GameTooltip:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffffffffAdd to Wishlist|r")
            GameTooltip:AddLine("Click to track this item on your loot wishlist.", 0.85, 0.85, 0.85)
            GameTooltip:AddLine("Triggers alerts and highlights whenever this item drops.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    starBtn:SetScript("OnLeave", function(self)
        if not self.isWishlisted and self.starIcon then
            self.starIcon:SetAlpha(0.25)
        end
        GameTooltip:Hide()
    end)

    starBtn:SetScript("OnClick", function(self)
        if btn.itemID and sfui.dungeonjournal and sfui.dungeonjournal.ToggleWishlist then
            local active = sfui.dungeonjournal.ToggleWishlist(btn.itemID)
            self.isWishlisted = active
            if active then
                if self.starIcon then
                    self.starIcon:SetDesaturated(false)
                    self.starIcon:SetAlpha(1.0)
                end
                btn:SetBackdropBorderColor(0.8, 0.27, 1.0, 0.7)
            else
                if self.starIcon then
                    self.starIcon:SetDesaturated(true)
                    self.starIcon:SetAlpha(0.25)
                end
                btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.8)
            end
            if GameTooltip:IsOwned(self) then
                self:GetScript("OnEnter")(self)
            end
        end
    end)

    -- Level info / Drop rate text (right-aligned before star)
    local reqText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.reqText = reqText
    reqText:SetPoint("RIGHT", starBtn, "LEFT", -6, 0)
    reqText:SetJustifyH("RIGHT")
    reqText:SetWordWrap(false)
    reqText:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Item Name
    local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameText = nameText
    nameText:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, -4)
    nameText:SetPoint("TOPRIGHT", starBtn, "TOPLEFT", -110, -4)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    -- Subtext: Slot & Subtype (e.g. "One-Hand · Sword" or "Leather · Chest")
    local typeText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.typeText = typeText
    typeText:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMRIGHT", 8, 4)
    typeText:SetPoint("BOTTOMRIGHT", starBtn, "BOTTOMLEFT", -110, 4)
    typeText:SetJustifyH("LEFT")
    typeText:SetWordWrap(false)
    typeText:SetTextColor(0.65, 0.65, 0.65, 1)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.2)

    pool[#pool + 1] = btn
    return btn
end

local function ReleaseAll(pool)
    for _, btn in ipairs(pool) do btn:Hide() end
end

-- ─── Chat Linking & Item Click Helpers ───────────────────────────────────────
local function ResolveItemLink(btn, fallbackItemID)
    local itemID = (btn and btn.itemID) or fallbackItemID
    local itemLink = btn and btn.link

    if not (itemLink and type(itemLink) == "string" and itemLink:find("|Hitem:")) and itemID then
        if common and common.get_item_info then
            local _, l = common.get_item_info(itemID)
            itemLink = l
        end
        if not itemLink and GetItemInfo then
            local _, l = GetItemInfo(itemID)
            itemLink = l
        end
        if not itemLink and C_Item and C_Item.GetItemInfo then
            local _, l = C_Item.GetItemInfo(itemID)
            itemLink = l
        end
        if itemLink and btn then
            btn.link = itemLink
        end
    end

    if not (itemLink and type(itemLink) == "string" and itemLink:find("|Hitem:")) and itemID then
        local rawName = (btn and btn.nameText and btn.nameText.GetText and btn.nameText:GetText()) or ("item #" .. itemID)
        local cleanName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local quality = 1
        if common and common.get_item_instant_info then
            local _, _, q = common.get_item_instant_info(itemID)
            quality = q or 1
        elseif C_Item and C_Item.GetItemInfoInstant then
            local _, _, q = C_Item.GetItemInfoInstant(itemID)
            quality = q or 1
        end
        local r, g, b = GetQualityColor(quality)
        local hex = string.format("ff%02x%02x%02x", math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5))
        itemLink = string.format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, itemID, cleanName)
        if btn then
            btn.link = itemLink
        end
    end

    return itemLink
end

local function InsertItemLinkIntoChat(link)
    if not link then return false end

    -- 1. Try Blizzard canonical ChatFrameUtil / ChatEdit handlers
    if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then
        return true
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
        return true
    end

    -- 2. Try HandleModifiedItemClick
    if HandleModifiedItemClick and HandleModifiedItemClick(link) then
        return true
    end

    -- 3. Fallback: Directly locate and insert into the active chat edit box
    local activeChat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
        or _G.ACTIVE_CHAT_EDIT_BOX
        or (_G.LAST_ACTIVE_CHAT_EDIT_BOX and (_G.LAST_ACTIVE_CHAT_EDIT_BOX:IsShown() or _G.LAST_ACTIVE_CHAT_EDIT_BOX:IsVisible()) and _G.LAST_ACTIVE_CHAT_EDIT_BOX)

    if activeChat and (activeChat:IsShown() or activeChat:IsVisible()) and activeChat.Insert then
        activeChat:Insert(link)
        if activeChat.SetFocus then
            activeChat:SetFocus()
        end
        return true
    end

    -- 4. Check Macro editor or Communities chat
    if _G.MacroFrameText and _G.MacroFrameText:IsShown() and _G.MacroFrameText:HasFocus() then
        _G.MacroFrameText:Insert(link)
        return true
    end
    if _G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsShown() and _G.CommunitiesFrame.ChatEditBox:HasFocus() then
        _G.CommunitiesFrame.ChatEditBox:Insert(link)
        return true
    end

    return false
end

-- ─── Render Loot Items ────────────────────────────────────────────────────────
local function RenderLoot(boss, dungeon)
    if not lootScroll or not lootContent then return end
    ReleaseAll(lootButtons)

    local pal    = theme.GetPalette()
    local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }

    -- Update Boss Header details
    if bossHeaderFrame then
        if boss then
            if boss.isAll then
                bossHeaderFrame.name:SetText("All Bosses")
                local dungeonName = (dungeon and dungeon.name) or "Dungeon"
                local numBosses = (dungeon and dungeon.bosses and #dungeon.bosses) or 0
                bossHeaderFrame.sub:SetText(dungeonName .. "  ·  " .. numBosses .. " boss encounters combined")

                local dropCount = (boss.items and #boss.items) or 0
                if dropCount > 0 then
                    bossHeaderFrame.count:SetText(dropCount .. " total drop" .. (dropCount > 1 and "s" or ""))
                    bossHeaderFrame.count:SetTextColor(accent[1], accent[2], accent[3], 1)
                else
                    bossHeaderFrame.count:SetText("no recorded drops")
                    bossHeaderFrame.count:SetTextColor(0.5, 0.5, 0.5, 1)
                end

                bossHeaderFrame.portrait:SetTexture(boss.icon or (dungeon and dungeon.icon) or 133743)
                bossHeaderFrame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if bossHeaderFrame.portraitFrame then
                    bossHeaderFrame.portraitFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
                    bossHeaderFrame.portraitFrame:Show()
                end
            else
                bossHeaderFrame.name:SetText(boss.name or "unknown encounter")
                local dungeonName = (dungeon and dungeon.name) or "dungeon"
                local lvlStr = boss.level and ("level " .. boss.level .. " encounter") or "boss encounter"
                bossHeaderFrame.sub:SetText(dungeonName .. "  ·  " .. lvlStr)

                local dropCount = (boss.items and #boss.items) or 0
                if dropCount > 0 then
                    bossHeaderFrame.count:SetText(dropCount .. " recorded drop" .. (dropCount > 1 and "s" or ""))
                    bossHeaderFrame.count:SetTextColor(accent[1], accent[2], accent[3], 1)
                else
                    bossHeaderFrame.count:SetText("no recorded drops")
                    bossHeaderFrame.count:SetTextColor(0.5, 0.5, 0.5, 1)
                end

                -- Update Header Portrait
                local set = false
                if boss.displayId and SetPortraitTextureFromCreatureDisplayID then
                    local ok = pcall(SetPortraitTextureFromCreatureDisplayID, bossHeaderFrame.portrait, boss.displayId)
                    if ok and bossHeaderFrame.portrait:GetTexture() then
                        bossHeaderFrame.portrait:SetTexCoord(0, 1, 0, 1)
                        set = true
                    end
                end
                if not set then
                    if boss.icon then
                        bossHeaderFrame.portrait:SetTexture(boss.icon)
                        bossHeaderFrame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    else
                        bossHeaderFrame.portrait:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                        bossHeaderFrame.portrait:SetTexCoord(0, 1, 0, 1)
                    end
                end
                if bossHeaderFrame.portraitFrame then
                    bossHeaderFrame.portraitFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
                    bossHeaderFrame.portraitFrame:Show()
                end
            end
        else
            bossHeaderFrame.name:SetText("select an encounter")
            bossHeaderFrame.sub:SetText("choose a boss from the list on the left")
            bossHeaderFrame.count:SetText("")
            if bossHeaderFrame.portrait then
                bossHeaderFrame.portrait:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                bossHeaderFrame.portrait:SetTexCoord(0, 1, 0, 1)
            end
            if bossHeaderFrame.portraitFrame then
                bossHeaderFrame.portraitFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
            end
        end
    end

    wipe(currentBossItemSet)
    if not boss or not boss.items or #boss.items == 0 then
        lootContent:SetHeight(10)
        if lootScroll and lootScroll.SetVerticalScroll then
            lootScroll:SetVerticalScroll(0)
        end
        if lootScroll and lootScroll.ScrollBar and lootScroll.ScrollBar.UpdateVisibility then
            lootScroll.ScrollBar:UpdateVisibility()
        end
        return
    end

    local y = 0
    local shownCount = 0

    for _, itemEntry in ipairs(boss.items) do
        local itemID = type(itemEntry) == "table" and (itemEntry.id or itemEntry[1]) or itemEntry
        itemID = tonumber(itemID)
        if itemID then
            currentBossItemSet[itemID] = true

            -- Query item data via project wrapper
            local name, link, quality, iLevel, reqLevel, class, subclass, _, equipSlot, icon, _, classID, subclassID = common.get_item_info(itemID)
            if not link and GetItemInfo then
                local _, l = GetItemInfo(itemID)
                link = l
            end

            if not name or not icon then
                -- Fallback instant info
                local instName, _, instQuality, _, _, _, _, _, instEquipLoc, instIcon, _, instClassID, instSubClassID = common.get_item_instant_info(itemID)
                name       = instName or ("item #" .. itemID)
                quality    = instQuality or 1
                icon       = instIcon or 134400
                equipSlot  = instEquipLoc
                classID    = classID or instClassID
                subclassID = subclassID or instSubClassID
                -- Request async cache population
                if common and common.request_item_load then
                    common.request_item_load(itemID)
                elseif _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                    pcall(_G.C_Item.RequestLoadItemDataByID, itemID)
                end
            end

            -- Filter check
            local itemLink = link or ("item:" .. itemID)
            if IsItemMatchingFilter(currentLootFilter, itemID, classID, subclassID, equipSlot, itemLink) then
                shownCount = shownCount + 1
                local btn = AcquireLootButton(lootButtons, lootContent)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT",  lootContent, "TOPLEFT",  0, -y)
                btn:SetPoint("TOPRIGHT", lootContent, "TOPRIGHT", 0, -y)
                btn:SetHeight(LOOT_ROW_H)

                btn.itemID = itemID
                btn.link   = link

                -- Wishlist state
                local isWish = sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted and sfui.dungeonjournal.IsWishlisted(itemID)
                btn.starBtn.isWishlisted = isWish
                if isWish then
                    if btn.starBtn.starIcon then
                        btn.starBtn.starIcon:SetDesaturated(false)
                        btn.starBtn.starIcon:SetAlpha(1.0)
                    end
                    btn:SetBackdropBorderColor(0.8, 0.27, 1.0, 0.7)
                else
                    if btn.starBtn.starIcon then
                        btn.starBtn.starIcon:SetDesaturated(true)
                        btn.starBtn.starIcon:SetAlpha(0.25)
                    end
                    btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.8)
                end

                local r, g, b = GetQualityColor(quality)

                -- Set Icon & Border
                btn.iconTex:SetTexture(icon or 134400)
                btn.iconBtn:SetBackdropBorderColor(r, g, b, 0.8)

                -- Name with quality color
                btn.nameText:SetText(name or ("item #" .. itemID))
                btn.nameText:SetTextColor(r, g, b, 1)

                -- Type / Subtype text
                local slotText = equipSlot and _G[equipSlot] or equipSlot
                local typeLabel = ""
                if slotText and subclass and subclass ~= "" then
                    typeLabel = tostring(slotText):lower() .. "  ·  " .. tostring(subclass):lower()
                elseif slotText then
                    typeLabel = tostring(slotText):lower()
                elseif subclass then
                    typeLabel = tostring(subclass):lower()
                elseif class then
                    typeLabel = tostring(class):lower()
                end
                if boss.isAll then
                    local source = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(itemID)
                    if source and source.bossName then
                        if typeLabel ~= "" then
                            typeLabel = typeLabel .. "  ·  |cff888888" .. tostring(source.bossName):lower() .. "|r"
                        else
                            typeLabel = "|cff888888" .. tostring(source.bossName):lower() .. "|r"
                        end
                    end
                end
                btn.typeText:SetText(typeLabel)

                -- Drop rate & Level info
                local dropRate = (type(itemEntry) == "table" and (itemEntry.dropRate or itemEntry.rate or itemEntry[2]))
                                 or (boss.dropRates and boss.dropRates[itemID])
                if not dropRate and boss.isAll then
                    local source = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(itemID)
                    if source and source.boss and source.boss.dropRates then
                        dropRate = source.boss.dropRates[itemID]
                    end
                end
                local rateStr = nil
                if dropRate then
                    local numRate = tonumber(dropRate)
                    if numRate and numRate > 0 and numRate < 1 then
                        rateStr = string.format("%d%%", math.floor(numRate * 100 + 0.5))
                    elseif numRate then
                        rateStr = string.format("%g%%", numRate)
                    else
                        rateStr = tostring(dropRate)
                    end
                end

                local reqStr = ""
                if reqLevel and reqLevel > 0 then
                    reqStr = "req " .. reqLevel
                elseif iLevel and iLevel > 0 then
                    reqStr = "ilvl " .. iLevel
                end

                if rateStr and reqStr ~= "" then
                    btn.reqText:SetText(string.format("|cff00e5ff%s|r  ·  %s", rateStr, reqStr))
                elseif rateStr then
                    btn.reqText:SetText(string.format("|cff00e5ff%s|r", rateStr))
                else
                    btn.reqText:SetText(reqStr)
                end

                -- Tooltips and Click actions
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local itemLink = ResolveItemLink(self, itemID)
                    if itemLink then
                        GameTooltip:SetHyperlink(itemLink)
                    else
                        GameTooltip:SetItemByID(itemID)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff888888<shift-click to link · ctrl-click to view>|r", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                btn:SetScript("OnClick", function(self, mouseBtn)
                    if mouseBtn == "LeftButton" then
                        local isChatLink = (IsModifiedClick and IsModifiedClick("CHATLINK")) or (IsShiftKeyDown and IsShiftKeyDown())
                        local isDressUp  = (IsModifiedClick and IsModifiedClick("DRESSUP")) or (IsControlKeyDown and IsControlKeyDown())

                        if isChatLink or isDressUp then
                            local itemLink = ResolveItemLink(self, itemID)
                            if not itemLink then return end

                            if isChatLink then
                                InsertItemLinkIntoChat(itemLink)
                            elseif isDressUp then
                                if not (HandleModifiedItemClick and HandleModifiedItemClick(itemLink)) then
                                    if DressUpItemLink then
                                        DressUpItemLink(itemLink)
                                    elseif DressUpLink then
                                        DressUpLink(itemLink)
                                    end
                                end
                            end
                        end
                    end
                end)

                btn:Show()
                y = y + LOOT_ROW_H + LOOT_ROW_PAD
            end
        end
    end

    -- Update count badge if filtered
    if bossHeaderFrame and bossHeaderFrame.count and boss and boss.items then
        local totalCount = #boss.items
        if currentLootFilter ~= "all" then
            if shownCount > 0 then
                bossHeaderFrame.count:SetText(string.format("%d of %d items", shownCount, totalCount))
                bossHeaderFrame.count:SetTextColor(accent[1], accent[2], accent[3], 1)
            else
                bossHeaderFrame.count:SetText(string.format("0 of %d items", totalCount))
                bossHeaderFrame.count:SetTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    lootContent:SetHeight(math.max(1, y))
    if lootScroll and lootScroll.ScrollBar and lootScroll.ScrollBar.UpdateVisibility then
        lootScroll.ScrollBar:UpdateVisibility()
    end
end

-- ─── Render Boss List ─────────────────────────────────────────────────────────
local function RefreshBossView()
    if not bossPanel or not bossPanel:IsShown() then return end

    local dungeon = GetCurrentDungeon()
    local encounters = GetEncounterList(dungeon)

    ReleaseAll(bossButtons)

    local savedBoss = DJ_DB().lastBoss or 1
    if savedBoss > #encounters then savedBoss = 1 end
    selectedBossIndex = savedBoss

    local pal    = theme.GetPalette()
    local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }

    local y = 0
    for idx, boss in ipairs(encounters) do
        local btn = AcquireBossButton(bossButtons, bossListContent)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  bossListContent, "TOPLEFT",  0, -y)
        btn:SetPoint("TOPRIGHT", bossListContent, "TOPRIGHT", 0, -y)
        btn:SetHeight(BOSS_BTN_H)

        -- Icon
        local set = false
        if boss.isAll then
            btn.icon:SetTexture(boss.icon or (dungeon and dungeon.icon) or 133743)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            set = true
        elseif boss.displayId and SetPortraitTextureFromCreatureDisplayID then
            local ok = pcall(SetPortraitTextureFromCreatureDisplayID, btn.icon, boss.displayId)
            if ok and btn.icon:GetTexture() then
                btn.icon:SetTexCoord(0, 1, 0, 1)
                set = true
            end
        end
        if not set then
            if boss.icon then
                btn.icon:SetTexture(boss.icon)
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                btn.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                btn.icon:SetTexCoord(0, 1, 0, 1)
            end
        end

        -- Name
        btn.nameText:SetText(boss.name or ("boss #" .. idx))

        -- Level
        if boss.isAll then
            btn.levelText:SetText(boss.subtitle or "all encounters")
        elseif boss.level then
            btn.levelText:SetText("level " .. boss.level)
        else
            btn.levelText:SetText("boss encounter")
        end

        -- Selection state
        local isSelected = (idx == selectedBossIndex)
        if isSelected then
            btn.nameText:SetTextColor(accent[1], accent[2], accent[3], 1)
            btn:SetBackdropColor(0.14, 0.14, 0.18, 0.95)
            btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
            if btn.icoFrame then
                btn.icoFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.85)
            end
        else
            btn.nameText:SetTextColor(0.85, 0.85, 0.85, 1)
            btn:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            if btn.icoFrame then
                btn.icoFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
            end
        end

        local currentIdx = idx
        btn:SetScript("OnClick", function()
            selectedBossIndex = currentIdx
            DJ_DB().lastBoss = currentIdx
            RefreshBossView()
        end)

        btn:Show()
        y = y + BOSS_BTN_H + BOSS_BTN_PAD
    end

    bossListContent:SetHeight(math.max(1, y))
    if bossListScroll and bossListScroll.ScrollBar and bossListScroll.ScrollBar.UpdateVisibility then
        bossListScroll.ScrollBar:UpdateVisibility()
    end

    -- Render the currently selected boss loot
    local currentBoss = encounters[selectedBossIndex]
    RenderLoot(currentBoss, dungeon)
end

-- ─── Debounced Item Load Refresh ──────────────────────────────────────────────
local isRefreshQueued = false

local function QueueLootRefresh(itemID)
    if not bossPanel or not bossPanel:IsShown() then return end
    if isRefreshQueued then return end
    if itemID and not currentBossItemSet[itemID] then return end

    isRefreshQueued = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0.15, function()
            isRefreshQueued = false
            if bossPanel and bossPanel:IsShown() then
                local dungeon = GetCurrentDungeon()
                local encounters = GetEncounterList(dungeon)
                local currentBoss = encounters[selectedBossIndex]
                if currentBoss then
                    RenderLoot(currentBoss, dungeon)
                end
            end
        end)
    else
        isRefreshQueued = false
    end
end

-- ─── Build UI Structure ───────────────────────────────────────────────────────
local function OnFrameCreated(arg1, arg2)
    local payload = (type(arg1) == "table" and arg1) or arg2
    if not payload or not payload.bossPanel then return end
    if lootScroll then return end -- already initialized
    bossPanel = payload.bossPanel

    -- ── Left Sub-Panel: Boss List Container ───────────────────────────────────
    local bossListContainer = CreateFrame("Frame", nil, bossPanel, "BackdropTemplate")
    bossListContainer:SetPoint("TOPLEFT",    bossPanel, "TOPLEFT",    0, 0)
    bossListContainer:SetPoint("BOTTOMLEFT", bossPanel, "BOTTOMLEFT", 0, 0)
    bossListContainer:SetWidth(BOSS_LIST_W)
    theme.ApplyContainerStyle(bossListContainer)

    bossListScroll = CreateFrame("ScrollFrame", "SfuiDJBossListScroll", bossListContainer, "UIPanelScrollFrameTemplate")
    bossListScroll:SetPoint("TOPLEFT",    bossListContainer, "TOPLEFT",     4, -4)
    bossListScroll:SetPoint("BOTTOMRIGHT",bossListContainer, "BOTTOMRIGHT", -22, 4)

    local BOSS_SCROLL_W = 174
    bossListContent = CreateFrame("Frame", nil, bossListScroll)
    bossListContent:SetSize(BOSS_SCROLL_W, 1)
    bossListScroll:SetScrollChild(bossListContent)

    if bossListScroll.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(bossListScroll.ScrollBar)
    end

    -- ── Right Sub-Panel: Loot & Details Container ─────────────────────────────
    local detailContainer = CreateFrame("Frame", nil, bossPanel, "BackdropTemplate")
    detailContainer:SetPoint("TOPLEFT",     bossListContainer, "TOPRIGHT",    8, 0)
    detailContainer:SetPoint("BOTTOMRIGHT", bossPanel,         "BOTTOMRIGHT", 0, 0)
    theme.ApplyContainerStyle(detailContainer)

    -- Top Header in Detail Container
    bossHeaderFrame = CreateFrame("Frame", nil, detailContainer)
    bossHeaderFrame:SetPoint("TOPLEFT",  detailContainer, "TOPLEFT",  10, -8)
    bossHeaderFrame:SetPoint("TOPRIGHT", detailContainer, "TOPRIGHT", -10, -8)
    bossHeaderFrame:SetHeight(48)

    -- Creature portrait in boss header
    local portraitFrame = CreateFrame("Frame", nil, bossHeaderFrame, "BackdropTemplate")
    bossHeaderFrame.portraitFrame = portraitFrame
    portraitFrame:SetSize(42, 42)
    portraitFrame:SetPoint("LEFT", bossHeaderFrame, "LEFT", 0, 0)
    portraitFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    portraitFrame:SetBackdropColor(0.04, 0.04, 0.06, 0.9)
    portraitFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    bossHeaderFrame.portrait = portrait
    portrait:SetAllPoints()

    local bossTitle = bossHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bossHeaderFrame.name = bossTitle
    bossTitle:SetPoint("TOPLEFT", portraitFrame, "TOPRIGHT", 10, -2)
    bossTitle:SetPoint("TOPRIGHT", bossHeaderFrame, "TOPRIGHT", -130, -2)
    bossTitle:SetJustifyH("LEFT")
    bossTitle:SetWordWrap(false)

    local bossSub = bossHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bossHeaderFrame.sub = bossSub
    bossSub:SetPoint("BOTTOMLEFT", portraitFrame, "BOTTOMRIGHT", 10, 4)
    bossSub:SetPoint("BOTTOMRIGHT", bossHeaderFrame, "BOTTOMRIGHT", -130, 4)
    bossSub:SetJustifyH("LEFT")
    bossSub:SetWordWrap(false)
    bossSub:SetTextColor(0.7, 0.7, 0.7, 1)

    local dropCountText = bossHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bossHeaderFrame.count = dropCountText
    dropCountText:SetPoint("BOTTOMRIGHT", bossHeaderFrame, "BOTTOMRIGHT", 0, 6)
    dropCountText:SetJustifyH("RIGHT")

    -- Divider under boss header
    local div = detailContainer:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT",  bossHeaderFrame, "BOTTOMLEFT",  0, -2)
    div:SetPoint("TOPRIGHT", bossHeaderFrame, "BOTTOMRIGHT", 0, -2)
    div:SetHeight(1)
    div:SetColorTexture(0.2, 0.2, 0.24, 0.8)

    -- Filter Bar Container (between header and loot scroll)
    local filterBar = CreateFrame("Frame", nil, detailContainer)
    filterBar:SetPoint("TOPLEFT",  div, "BOTTOMLEFT",  0, -4)
    filterBar:SetPoint("TOPRIGHT", div, "BOTTOMRIGHT", 0, -4)
    filterBar:SetHeight(22)

    local function UpdateFilterPills()
        local pal    = theme.GetPalette()
        local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
        for _, pBtn in ipairs(filterButtons) do
            local isSel = (pBtn.filterKey == currentLootFilter)
            if isSel then
                pBtn:SetBackdropColor(accent[1], accent[2], accent[3], 0.22)
                pBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
                pBtn.label:SetTextColor(accent[1], accent[2], accent[3], 1)
            else
                pBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.6)
                pBtn:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.6)
                pBtn.label:SetTextColor(0.65, 0.65, 0.7, 1)
            end
        end
    end

    local pillX = 0
    for _, def in ipairs(FILTER_BUTTONS) do
        local pBtn = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
        pBtn.filterKey = def.key
        pBtn:SetHeight(18)
        pBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        pBtn:SetPoint("LEFT", filterBar, "LEFT", pillX, 0)

        local pLbl = pBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pBtn.label = pLbl
        pLbl:SetPoint("CENTER", pBtn, "CENTER", 0, 0)
        pLbl:SetText(def.label)

        local textW = pLbl:GetStringWidth()
        local minW = (def.key == "wishlist") and 76 or 38
        local extraPad = (def.key == "wishlist") and 26 or 18
        local btnW = math.max(minW, math.floor(textW + extraPad))
        pBtn:SetWidth(btnW)
        pillX = pillX + btnW + 6

        pBtn:SetScript("OnClick", function()
            currentLootFilter = def.key
            UpdateFilterPills()
            local dungeon = GetCurrentDungeon()
            local encounters = GetEncounterList(dungeon)
            local currentBoss = encounters[selectedBossIndex]
            if currentBoss then
                RenderLoot(currentBoss, dungeon)
            end
        end)

        pBtn:SetScript("OnEnter", function(self)
            if self.filterKey ~= currentLootFilter then
                self:SetBackdropBorderColor(0.4, 0.4, 0.48, 0.9)
                self.label:SetTextColor(0.9, 0.9, 0.95, 1)
            end
        end)
        pBtn:SetScript("OnLeave", function()
            UpdateFilterPills()
        end)

        filterButtons[#filterButtons + 1] = pBtn
    end

    UpdateFilterPills()

    -- Loot ScrollFrame (width: 428 - 10 - 22 = 396)
    lootScroll = CreateFrame("ScrollFrame", "SfuiDJLootScroll", detailContainer, "UIPanelScrollFrameTemplate")
    lootScroll:SetPoint("TOPLEFT",     filterBar,       "BOTTOMLEFT",   0, -6)
    lootScroll:SetPoint("BOTTOMRIGHT", detailContainer, "BOTTOMRIGHT", -22, 8)

    local LOOT_SCROLL_W = 396
    lootContent = CreateFrame("Frame", nil, lootScroll)
    lootContent:SetSize(LOOT_SCROLL_W, 1)
    lootScroll:SetScrollChild(lootContent)

    if lootScroll.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(lootScroll.ScrollBar)
    end

    -- Register with orchestrator
    sfui.dungeonjournal._registerBosses(RefreshBossView)

    RefreshBossView()
end

sfui.dungeonjournal._initBosses = OnFrameCreated

-- ─── Message & Event Hooks ───────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_FRAME_CREATED", OnFrameCreated)
    sfui.events.RegisterMessage("SFUI_DJ_CLEAR_CACHE", function()
        bossButtons = {}
        lootButtons = {}
        RefreshBossView()
    end)
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", function()
        if bossPanel and bossPanel:IsShown() then
            local dungeon = GetCurrentDungeon()
            local encounters = GetEncounterList(dungeon)
            local currentBoss = encounters[selectedBossIndex]
            if currentBoss then
                RenderLoot(currentBoss, dungeon)
            end
        end
    end)
    sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function()
        if bossPanel and bossPanel:IsShown() then
            local dungeon = GetCurrentDungeon()
            local encounters = GetEncounterList(dungeon)
            local currentBoss = encounters[selectedBossIndex]
            if currentBoss then
                RenderLoot(currentBoss, dungeon)
            end
        end
    end)
end

if sfui.events and sfui.events.RegisterEvent then
    -- Debounced item cache updates
    sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
        if success ~= false then
            QueueLootRefresh(itemID)
        end
    end)
    sfui.events.RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
        if success ~= false then
            QueueLootRefresh(itemID)
        end
    end)
end
