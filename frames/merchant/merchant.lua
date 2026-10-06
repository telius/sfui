local addonName, addon = ...
---@diagnostic disable: undefined-global
-- frames/merchant/merchant.lua
-- Custom 4x7 grid merchant frame, item buttons, scrollbar, and event wiring for sfui

sfui = sfui or {}
sfui.merchant = sfui.merchant or {}

local common = sfui.common
local issecretvalue = common.issecretvalue or _G.issecretvalue
local get_item_id = common.get_item_id_from_link
local cfg = sfui.config.merchant
local app = sfui.config.appearance
local NUM_ROWS = cfg.grid.rows
local NUM_COLS = cfg.grid.cols
local ITEMS_PER_PAGE = NUM_ROWS * NUM_COLS

local isWarlockCamelot = (sfui.isCamelot or sfui.isClassic) and (sfui.common.get_player_class() == "WARLOCK")

local GameTooltip = sfui.common.get_tooltip()
local GameTooltip_Hide = sfui.common.hide_tooltip

--------------------------------------------------------------------------------
-- Main Merchant Window & Header
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "SfuiMerchantFrame", UIParent, "BackdropTemplate")
frame:SetSize(cfg.frame.width, cfg.frame.height)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame.itemHover = nil
sfui.merchant.frame = frame

local headerFrame = CreateFrame("Frame", "SfuiMerchantHeader", frame)
headerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
headerFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
headerFrame:SetHeight(50)
headerFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 15)
headerFrame:EnableMouse(false)
frame.headerFrame = headerFrame

local closeBtn = common.create_close_button(frame, function() frame:Hide() end, 20)
closeBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
frame.closeBtn = closeBtn

local CreateFlatButton = common.create_flat_button
local filterDropdownBtn = CreateFlatButton(frame, "showing all", 100, 20)
filterDropdownBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
filterDropdownBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
frame.filterDropdownBtn = filterDropdownBtn

local function refresh_frame_levels()
    local base = frame:GetFrameLevel() or 1
    if frame.sfuiThemeLayers and frame.sfuiThemeLayers.borderFrame then
        frame.sfuiThemeLayers.borderFrame:SetFrameLevel(base + 1)
    end
    if headerFrame then
        headerFrame:SetFrameLevel(base + 15)
    end
    if filterDropdownBtn then
        filterDropdownBtn:SetFrameLevel(base + 20)
    end
    if closeBtn then
        closeBtn:SetFrameLevel(base + 20)
    end
end
frame:HookScript("OnShow", refresh_frame_levels)

sfui.theme.ApplyWindowStyle(frame)
sfui.theme.RegisterWindow(frame, function(f, pal)
    refresh_frame_levels()
    if f.merchantName then
        f.merchantName:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3])
    end
end)

frame:Hide()
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

frame.portrait = headerFrame:CreateTexture(nil, "OVERLAY", nil, 2)
frame.portrait:SetSize(60, 60)
frame.portrait:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 10, 20)

frame.merchantName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.merchantName:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 80, -6)
frame.merchantName:SetJustifyH("LEFT")

frame.merchantTitle = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.merchantTitle:SetPoint("TOPLEFT", frame.merchantName, "BOTTOMLEFT", 0, -2)
frame.merchantTitle:SetJustifyH("LEFT")

filterDropdownBtn:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
        rootDescription:SetTag("MENU_MERCHANT_FILTER")

        rootDescription:CreateButton("All Items", function()
            sfui.merchant.lootFilterState = 0
            if SfuiDB.merchant then SfuiDB.merchant.lootFilterState = 0 end
            self:SetText("showing all")
            sfui.merchant.reset_scroll_and_rebuild()
        end)
        rootDescription:CreateButton("Current Class", function()
            sfui.merchant.lootFilterState = 1
            if SfuiDB.merchant then SfuiDB.merchant.lootFilterState = 1 end
            self:SetText("current class")
            sfui.merchant.reset_scroll_and_rebuild()
        end)
        rootDescription:CreateButton("Current Specialization", function()
            sfui.merchant.lootFilterState = 2
            if SfuiDB.merchant then SfuiDB.merchant.lootFilterState = 2 end
            self:SetText("current spec")
            sfui.merchant.reset_scroll_and_rebuild()
        end)
    end)
end)

-- Initialize filter state from DB on load
frame:HookScript("OnShow", function()
    if SfuiDB and SfuiDB.merchant and SfuiDB.merchant.lootFilterState then
        sfui.merchant.lootFilterState = SfuiDB.merchant.lootFilterState
        if sfui.merchant.lootFilterState == 0 then
            filterDropdownBtn:SetText("showing all")
        elseif sfui.merchant.lootFilterState == 1 then
            filterDropdownBtn:SetText("current class")
        elseif sfui.merchant.lootFilterState == 2 then
            filterDropdownBtn:SetText("current spec")
        end
    end
end)

--------------------------------------------------------------------------------
-- Item Grid Buttons (4x7)
--------------------------------------------------------------------------------

local buttons = {}
sfui.merchant.buttons = buttons

function sfui.merchant.create_item_button(id, parent)
    local btn = CreateFrame("Button", "SfuiMerchantItem" .. id, parent, "BackdropTemplate")
    btn:SetSize(190, 45)

    local iconWrap = CreateFrame("Button", nil, btn, "BackdropTemplate")
    iconWrap:SetSize(40, 40)
    iconWrap:SetPoint("LEFT", 2, 0)
    iconWrap:EnableMouse(false)
    btn.iconWrap = iconWrap
    btn.icon = iconWrap:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(iconWrap)

    common.apply_square_icon_style(iconWrap, btn.icon)

    btn.nameStub = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameStub:SetPoint("TOPLEFT", iconWrap, "TOPRIGHT", 5, 2)
    btn.nameStub:SetJustifyH("LEFT")

    btn.subName = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.subName:SetPoint("TOPLEFT", btn.nameStub, "BOTTOMLEFT", 0, -1)
    btn.subName:SetJustifyH("LEFT")
    btn.subName:SetTextColor(app.dimTextColor[1], app.dimTextColor[2], app.dimTextColor[3], 1)

    btn.price = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.price:SetPoint("BOTTOMLEFT", iconWrap, "BOTTOMRIGHT", 5, 0)
    btn.price:SetJustifyH("LEFT")

    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetPoint("BOTTOMRIGHT", iconWrap, -2, 2)

    btn.lockBackground = btn:CreateTexture(nil, "BACKGROUND")
    btn.lockBackground:SetAllPoints(btn)
    btn.lockBackground:SetColorTexture(app.lockColor[1], app.lockColor[2], app.lockColor[3], app.lockColor[4])
    btn.lockBackground:Hide()

    btn.lockReason = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.lockReason:SetPoint("TOPLEFT", btn.nameStub, "BOTTOMLEFT", 0, -1)
    btn.lockReason:SetWidth(145)
    btn.lockReason:SetMaxLines(1)
    btn.lockReason:SetWordWrap(false)
    btn.lockReason:SetJustifyH("LEFT")
    btn.lockReason:SetTextColor(app.errorColor[1], app.errorColor[2], app.errorColor[3], 1)
    btn.lockReason:Hide()

    btn.check = btn:CreateTexture(nil, "OVERLAY")
    btn.check:SetSize(20, 20)
    btn.check:SetPoint("TOPRIGHT", -2, -2)
    btn.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    btn.check:Hide()

    btn.unknownDecor = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    btn.unknownDecor:SetPoint("TOPRIGHT", -6, -4)
    btn.unknownDecor:SetText("!")
    btn.unknownDecor:SetTextColor(app.goldColor[1], app.goldColor[2], app.goldColor[3], 1)
    btn.unknownDecor:Hide()

    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    btn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.hasItem then
            if sfui.merchant.mode == "buyback" then
                GameTooltip:SetBuybackItem(self:GetID())
                if IsModifiedClick and IsModifiedClick("DRESSUP") and self.hasItem then
                    if ShowInspectCursor then ShowInspectCursor() end
                elseif ShowBuybackSellCursor then
                    ShowBuybackSellCursor(self:GetID())
                end
            else
                GameTooltip:SetMerchantItem(self:GetID())
                if GameTooltip_ShowCompareItem then
                    GameTooltip_ShowCompareItem(GameTooltip)
                end
                if isWarlockCamelot then
                    local link = GetMerchantItemLink(self:GetID())
                    if link and link:find("Grimoire", 1, true) and sfui.merchant.is_pet_spell_known and sfui.merchant.is_pet_spell_known(link) then
                        local alreadyShown = false
                        if C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
                            local tip = C_TooltipInfo.GetMerchantItem(self:GetID())
                            if tip and tip.lines then
                                for _, line in ipairs(tip.lines) do
                                    if line.leftText and (line.leftText == ITEM_SPELL_KNOWN or line.leftText == "Already known") then
                                        alreadyShown = true
                                        break
                                    end
                                end
                            end
                        end
                        if not alreadyShown then
                            GameTooltip:AddLine(ITEM_SPELL_KNOWN or "Already known", 1, 0.1, 0.1)
                        end
                    end
                end
            end
            frame.itemHover = self:GetID()
        elseif self.link then
            GameTooltip:SetHyperlink(self.link)
            if GameTooltip_ShowCompareItem then
                GameTooltip_ShowCompareItem(GameTooltip)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        GameTooltip_Hide()
        frame.itemHover = nil
    end)

    btn:SetScript("OnClick", function(self, button)
        if self.hasItem then
            if IsModifiedClick() then
                if sfui.merchant.mode == "buyback" then
                    local link = GetBuybackItemLink(self:GetID())
                    if link then HandleModifiedItemClick(link) end
                else
                    local link = GetMerchantItemLink(self:GetID())
                    if link and HandleModifiedItemClick(link) then return end

                    if IsModifiedClick("SPLITSTACK") and button == "RightButton" then
                        sfui.merchant.open_stack_split(self:GetID())
                        return
                    end
                end
                return
            end

            if sfui.merchant.mode == "buyback" then
                BuybackItem(self:GetID())
            else
                if button == "RightButton" then
                    BuyMerchantItem(self:GetID())
                else
                    PickupMerchantItem(self:GetID())
                end
            end
        end
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    common.sync_masque(iconWrap, { Icon = btn.icon })

    return btn
end

for i = 1, ITEMS_PER_PAGE do
    local btn = sfui.merchant.create_item_button(i, frame)
    local row = math.floor((i - 1) / NUM_COLS)
    local col = (i - 1) % NUM_COLS

    btn:SetPoint("TOPLEFT", cfg.grid.offset_x + (col * cfg.grid.spacing_x),
        cfg.grid.offset_y - (row * cfg.grid.spacing_y))
    buttons[i] = btn
end

--------------------------------------------------------------------------------
-- ScrollBar & Wheel Navigation
--------------------------------------------------------------------------------

local scrollBar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
scrollBar:SetOrientation("VERTICAL")
scrollBar:SetPoint("TOPRIGHT", -cfg.scrollbar.right_offset, cfg.grid.offset_y)
scrollBar:SetPoint("BOTTOMRIGHT", -cfg.scrollbar.right_offset, 65)
scrollBar:SetWidth(cfg.scrollbar.width)
scrollBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
})
scrollBar:SetBackdropColor(0, 0, 0, 0.3)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)
scrollBar:SetScript("OnValueChanged", function(self, value)
    local newOffset = math.floor(value) * NUM_COLS

    if sfui.merchant.scrollOffset ~= newOffset then
        sfui.merchant.scrollOffset = newOffset
        sfui.merchant.update_merchant()
    end
end)

local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
thumb:SetSize(6, 30)
thumb:SetColorTexture(app.white[1], app.white[2], app.white[3], 1)
scrollBar:SetThumbTexture(thumb)
frame.scrollBar = scrollBar

frame:SetScript("OnMouseWheel", function(self, delta)
    local min, max = scrollBar:GetMinMaxValues()
    local val = scrollBar:GetValue()
    local step = 1 -- Scroll 1 row
    if delta > 0 then
        val = val - step
    else
        val = val + step
    end

    if val < min then val = min end
    if val > max then val = max end

    scrollBar:SetValue(val)
end)

-- Initialize bottom utility bar
frame.utilityBar = sfui.merchant.create_utility_bar(frame)

--------------------------------------------------------------------------------
-- Grid Population & Display Update
--------------------------------------------------------------------------------

sfui.merchant.update_merchant = function()
    local indices = sfui.merchant.filteredIndices or {}
    for i = 1, ITEMS_PER_PAGE do
        local btn, index = buttons[i], indices[sfui.merchant.scrollOffset + i]
        if index then
            local data = sfui.merchant.get_item_data(index, sfui.merchant.mode)
            if data then
                btn:SetID(index); btn.hasItem, btn.link = true, data.link
                btn.icon:SetTexture(data.texture or 134400)

                -- Sync Masque state
                common.sync_masque(btn.iconWrap, { Icon = btn.icon })

                local slot = (data.equipLoc and data.equipLoc ~= "" and _G[data.equipLoc]) or ""
                local typeText = (slot ~= "" and slot) or data.subType or ""
                if data.classID == 4 and data.subClassID and data.subClassID <= 4 and data.subType ~= slot then
                    typeText = slot .. (data.subType ~= "" and " - " .. data.subType or "")
                end
                btn.subName:SetText(typeText == "Other" and "" or typeText)

                local itemID = data.link and get_item_id(data.link)
                local grantsXp = sfui.merchant.item_grants_decor_xp(itemID, data.link)

                if grantsXp then
                    btn.unknownDecor:Show()
                else
                    btn.unknownDecor:Hide()
                end
                btn.check:Hide()

                local r, g, b = C_Item.GetItemQualityColor(data.quality or 1)
                btn.nameStub:SetTextColor(r, g, b); btn.nameStub:SetText(common.shorten_name(data.name, 22))

                local cost = (data.price and data.price > 0) and
                    ((GetMoney() < data.price and "|cffff0000" or "|cffffffff") .. common.SafeGetCoinTextureString(data.price) .. "|r") or
                    ""
                if data.hasExtendedCost then
                    for j = 1, GetMerchantItemCostInfo(index) do
                        local tex, val, clink = GetMerchantItemCostItem(index, j)
                        if tex and val then
                            local ok = true
                            if clink then
                                local cid = tonumber(string.match(clink, "currency:(%d+)"))
                                ok = cid and (common.get_currency_quantity(cid) >= val) or
                                    (common.get_item_count(clink) >= val)
                            end
                            cost = cost ..
                                (cost ~= "" and " " or "") ..
                                (ok and "|cffffffff" or "|cffff0000") ..
                                BreakUpLargeNumbers(val) .. " |T" .. tex .. ":12:12:0:0|t|r"
                        end
                    end
                end
                btn.price:SetText(cost); btn.count:SetText(data.stackCount > 1 and data.stackCount or "")

                local id = get_item_id(data.link)
                local locked, reason = sfui.merchant.get_item_lock_status(index, id, data.isUsable)

                if locked then
                    btn.lockBackground:Show(); btn.lockReason:SetText(reason); btn.lockReason:Show(); btn.subName:Hide()
                    btn.icon:SetVertexColor(1, 0.1, 0.1); btn.icon:SetDesaturated(true)
                else
                    btn.lockBackground:Hide(); btn.lockReason:Hide(); btn.subName:Show()
                    local tinted = false
                    if (SfuiDB and SfuiDB.recipesTintIcons ~= false) and id and sfui.recipes.IsRecipe(id) then
                        local _, color = sfui.recipes.GetRecipeStatus(id)
                        if color then
                            btn.icon:SetVertexColor(color.r, color.g, color.b)
                            btn.icon:SetDesaturated(false)
                            tinted = true
                        end
                    end
                    if not tinted then
                        btn.icon:SetVertexColor(1, 1, 1); btn.icon:SetDesaturated(false)
                    end
                end
                btn:Show()
            else
                btn.check:Hide(); btn.unknownDecor:Hide(); btn:Hide()
            end
        else
            btn.check:Hide(); btn.unknownDecor:Hide(); btn:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- Header Information
--------------------------------------------------------------------------------

local function update_header()
    local unit = "npc"
    if not UnitExists(unit) then unit = "target" end

    SetPortraitTexture(frame.portrait, unit)
    frame.merchantName:SetText(UnitName(unit) or "Merchant")

    local titleText = ""
    local data = C_TooltipInfo.GetUnit(unit)
    if data and data.lines then
        local line2 = data.lines[2] and data.lines[2].leftText
        if line2 and not issecretvalue(line2) and type(line2) == "string" then
            if not string.find(line2, "Level") then
                titleText = line2
            else
                local line3 = data.lines[3] and data.lines[3].leftText
                if line3 and not issecretvalue(line3) and type(line3) == "string" then
                    titleText = line3
                end
            end
        end
    end
    frame.merchantTitle:SetText(titleText)
end

--------------------------------------------------------------------------------
-- Central Event Wiring
--------------------------------------------------------------------------------

local isSystemClose = false

sfui.events.RegisterEvent("MERCHANT_SHOW", function()
    wipe(sfui.merchant.lockCache)
    update_header()
    sfui.merchant.reset_scroll_and_rebuild()
    if not SfuiDB.enableMerchant then return end
    frame:Show()
    sfui.merchant.build_item_list()

    if MerchantFrame then
        MerchantFrame:SetAlpha(0)
        C_Timer.After(0.01, function()
            MerchantFrame:SetAlpha(0)
            if not (MerchantFrame.IsProtected and MerchantFrame:IsProtected()) and MerchantFrame.EnableMouse then
                pcall(MerchantFrame.EnableMouse, MerchantFrame, false)
            end
            MerchantFrame:SetFrameStrata("BACKGROUND")
            MerchantFrame:SetScale(0.001)
            MerchantFrame:ClearAllPoints()
            MerchantFrame:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -1000, 1000)
        end)
    end
end)

sfui.events.RegisterEvent("MERCHANT_CLOSED", function()
    wipe(sfui.merchant.lockCache)
    if sfui.merchant.decorXpCache then
        wipe(sfui.merchant.decorXpCache)
    end
    isSystemClose = true
    frame:Hide()
    isSystemClose = false
    GameTooltip_Hide()
    if MerchantFrame then
        MerchantFrame:SetAlpha(1)
        if not (MerchantFrame.IsProtected and MerchantFrame:IsProtected()) and MerchantFrame.EnableMouse then
            pcall(MerchantFrame.EnableMouse, MerchantFrame, true)
        end
        MerchantFrame:SetFrameStrata("HIGH")
        MerchantFrame:SetScale(1)
    end
end)

local function on_merchant_update(event, ...)
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if not success or not itemID then return end

        if sfui.merchant.decorXpCache then
            sfui.merchant.decorXpCache[itemID] = nil
        end

        -- Only rebuild if the item is actually in the merchant's current stock
        local found = false
        for i = 1, GetMerchantNumItems() do
            local link = GetMerchantItemLink(i)
            if link and get_item_id(link) == itemID then
                found = true
                break
            end
        end
        if not found then return end
    end

    if frame:IsShown() then
        if not frame.updatePending then
            frame.updatePending = true
            C_Timer.After(0.05, function()
                if frame:IsShown() then sfui.merchant.build_item_list() end
                frame.updatePending = false
            end)
        end
    end
end
sfui.events.RegisterEvent("MERCHANT_UPDATE",       on_merchant_update)
sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", on_merchant_update)

tinsert(UISpecialFrames, "SfuiMerchantFrame")
frame:Hide()

function sfui.merchant_debug_info()
    local pCount = 0
    local pool = sfui.merchant.tablePool or {}
    for _ in pairs(pool) do pCount = pCount + 1 end
    return {
        tablePool = pCount,
        frameCreated = frame ~= nil,
        frameShown = frame and frame:IsShown() or false,
    }
end

if sfui.RegisterModule then
    sfui.merchant.GetDebugInfo = sfui.merchant_debug_info
    sfui.RegisterModule("merchant", sfui.merchant)
end
