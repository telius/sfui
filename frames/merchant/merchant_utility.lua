local addonName, addon = ...
---@diagnostic disable: undefined-global
-- frames/merchant/merchant_utility.lua
-- Utility bar, currency footer display, stack split popup, repairs, and junk selling for sfui merchant

sfui = sfui or {}
sfui.merchant = sfui.merchant or {}

local common = sfui.common
local issecretvalue = common.issecretvalue or _G.issecretvalue
local cfg = sfui.config.merchant
local app = sfui.config.appearance

local GameTooltip = sfui.common.get_tooltip()
local GameTooltip_Hide = sfui.common.hide_tooltip
sfui.merchant.GameTooltip_Hide = GameTooltip_Hide

local CreateFlatButton = common.create_flat_button
local sortedCurrencyItems = {}

--------------------------------------------------------------------------------
-- Stack Split Quantity Dialog
--------------------------------------------------------------------------------

function sfui.merchant.create_stack_split_frame(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(180, 110)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(app.backdropColor[1], app.backdropColor[2], app.backdropColor[3], 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOP", 0, -8)
    f.title:SetText("enter quantity")

    local eb = CreateFrame("EditBox", nil, f)
    eb:SetSize(80, 24)
    eb:SetPoint("TOP", 0, -30)
    eb:SetFontObject("ChatFontNormal")
    eb:SetJustifyH("CENTER")
    eb:SetNumeric(true)
    eb:SetAutoFocus(true)

    local eb_bg = eb:CreateTexture(nil, "BACKGROUND")
    eb_bg:SetAllPoints()
    eb_bg:SetColorTexture(app.widgetBackdropColor[1], app.widgetBackdropColor[2], app.widgetBackdropColor[3], 1)

    eb:SetScript("OnEnterPressed", function() f.buyBtn:Click() end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.editBox = eb

    f.maxBtn = CreateFlatButton(f, "Max", 40, 24)
    f.maxBtn:SetPoint("LEFT", eb, "RIGHT", 5, 0)
    common.set_color(f.maxBtn, "black")
    f.maxBtn:SetScript("OnClick", function()
        local maxStack = f.maxStack or 1
        local price = f.price or 0
        local money = GetMoney()
        local affordable = price > 0 and math.floor(money / price) or maxStack

        local stackSize = f.stackCount or 1
        local maxPurchases = math.floor(maxStack / stackSize)
        local canBuy = math.min(affordable, maxPurchases)
        if canBuy < 1 then canBuy = 1 end

        eb:SetText(canBuy)
        eb:SetFocus()
    end)

    f.buyBtn = CreateFlatButton(f, "Buy", 70, 24)
    f.buyBtn:SetPoint("BOTTOMLEFT", 10, 10)
    common.set_color(f.buyBtn, "black")
    f.buyBtn:SetScript("OnClick", function()
        local val = tonumber(eb:GetText()) or 1
        if val > 0 then
            BuyMerchantItem(f.index, val)
        end
        f:Hide()
    end)

    f.cancelBtn = CreateFlatButton(f, "Cancel", 70, 24)
    f.cancelBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    common.set_color(f.cancelBtn, "black")
    f.cancelBtn:SetScript("OnClick", function() f:Hide() end)

    return f
end

function sfui.merchant.open_stack_split(index)
    if not sfui.merchant.stackSplitFrame then
        local parent = sfui.merchant.frame or UIParent
        sfui.merchant.stackSplitFrame = sfui.merchant.create_stack_split_frame(parent)
    end

    local f = sfui.merchant.stackSplitFrame
    f.index = index
    f.editBox:SetText("1")

    local info = sfui.api.GetMerchantItemInfo(index)
    local name, price, stackCount, link
    if info then
        name = info.name
        price = info.price
        stackCount = info.stackCount
        link = info.hyperlink
    end
    if link then
        local _, _, _, _, _, _, _, itemStackCount = sfui.common.get_item_info(link)
        f.maxStack = itemStackCount
    else
        f.maxStack = 9999
    end
    f.price = price
    f.stackCount = stackCount -- Amount received per buy

    f:Show()
    f.editBox:SetFocus()
end

--------------------------------------------------------------------------------
-- Currency Footer Bar
--------------------------------------------------------------------------------

function sfui.merchant.update_currency_display(frame)
    frame.currencyDisplays = frame.currencyDisplays or {}
    local displays = frame.currencyDisplays

    for _, f in pairs(displays) do f:Hide() end

    local cache = sfui.merchant.currencyCache or {}

    -- Memory optimization: Reuse sorted table and pool its entries
    sfui.merchant.releaseCache(sortedCurrencyItems)
    wipe(sortedCurrencyItems)

    for name, data in pairs(cache) do
        local entry = sfui.merchant.getTable()
        entry.name = name
        entry.data = data
        table.insert(sortedCurrencyItems, entry)
    end

    table.sort(sortedCurrencyItems, function(a, b)
        if a.name == "Gold" then return false end -- Gold always last (greater)
        if b.name == "Gold" then return true end
        return a.name < b.name
    end)

    if #sortedCurrencyItems == 0 then return end

    if not frame.currencyContainer then
        frame.currencyContainer = CreateFrame("Frame", nil, frame)
        frame.currencyContainer:SetHeight(cfg.currency.height)
        frame.currencyContainer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, cfg.currency.bottom_offset)
    end
    local container = frame.currencyContainer
    container:Show()

    frame._activeCurrencyDisplays = frame._activeCurrencyDisplays or {}
    local activeDisplays = frame._activeCurrencyDisplays
    wipe(activeDisplays)
    local totalWidth = 0

    for i, item in ipairs(sortedCurrencyItems) do
        local idx = i
        local data = item.data

        local display = displays[idx]
        if not display then
            display = CreateFrame("Frame", nil, container)
            display:SetSize(100, 20)

            display.icon = display:CreateTexture(nil, "ARTWORK")
            display.icon:SetSize(16, 16)
            display.icon:SetPoint("LEFT")

            display.text = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            display.text:SetPoint("LEFT", display.icon, "RIGHT", 5, 0)

            display:EnableMouse(true)
            display:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.type == "item" then
                    GameTooltip:SetItemByID(self.currencyID)
                elseif self.currencyID then
                    GameTooltip:SetCurrencyByID(self.currencyID)
                elseif self.currencyName == "Gold" then
                    GameTooltip:SetText("gold")
                    GameTooltip:AddLine("total money on character", 1, 1, 1)
                else
                    GameTooltip:SetText(self.currencyName or "Currency")
                end
                GameTooltip:Show()
            end)
            display:SetScript("OnLeave", function()
                if GameTooltip and GameTooltip:IsShown() then
                    GameTooltip:Hide()
                end
            end)

            displays[idx] = display
        end

        display.icon:SetTexture(data.texture)
        display.currencyID = data.id     -- Store ID for tooltip
        display.currencyName = item.name -- Store Name for fallback
        display.type = data.type         -- Store Type for tooltip

        local count = data.count
        local displayText
        if count >= 1000000 then
            displayText = string.format("%.1fM", count / 1000000)
        elseif count >= 1000 then
            displayText = string.format("%.1fK", count / 1000)
        else
            displayText = tostring(count)
        end
        display.text:SetText(displayText)

        local textWidth = display.text:GetStringWidth()
        local width = 16 + 5 + textWidth + 2
        display:SetWidth(width)
        display:Show()

        activeDisplays[i] = display

        if totalWidth > 0 then totalWidth = totalWidth + 15 end -- Gap
        totalWidth = totalWidth + width
    end

    container:SetWidth(totalWidth)

    local prev
    for i, display in ipairs(activeDisplays) do
        display:ClearAllPoints()
        if i == 1 then
            display:SetPoint("LEFT", container, "LEFT", 0, 0)
        else
            display:SetPoint("LEFT", prev, "RIGHT", 15, 0)
        end
        prev = display
    end
end

--------------------------------------------------------------------------------
-- Bottom Utility Bar & Automation Buttons
--------------------------------------------------------------------------------

local function update_filter_button_style(self)
    if sfui.merchant.filterKnown == 2 then
        self:SetText("known: warband")
        common.set_color(self, cfg.button_colors.filter_active)
    elseif sfui.merchant.filterKnown == 1 or sfui.merchant.filterKnown == true then
        self:SetText("known: char")
        common.set_color(self, cfg.button_colors.filter_active)
    else
        self:SetText("known: show all")
        common.set_color(self, cfg.button_colors.filter_inactive)
    end
end

function sfui.merchant.create_utility_bar(frame)
    local utilityBar = CreateFrame("Frame", nil, frame)
    utilityBar:SetHeight(cfg.utility_bar.height)
    utilityBar:SetPoint("BOTTOMLEFT", 10, cfg.utility_bar.bottom_offset)
    utilityBar:SetPoint("BOTTOMRIGHT", -10, cfg.utility_bar.bottom_offset)

    -- Buyback / Merchant toggle button
    local buybackBtn = CreateFlatButton(utilityBar, "buyback", cfg.utility_bar.button_small,
        cfg.utility_bar.button_height)
    buybackBtn:SetPoint("LEFT", 0, 0)
    buybackBtn:SetScript("OnClick", function(self)
        if sfui.merchant.mode == "merchant" then
            sfui.merchant.mode = "buyback"
            self:SetText("merchant")
        else
            sfui.merchant.mode = "merchant"
            self:SetText("buyback")
        end
        sfui.merchant.reset_scroll_and_rebuild()
    end)
    sfui.merchant.buybackBtn = buybackBtn

    -- Known recipe / item filter toggle button
    local filterBtn = CreateFlatButton(utilityBar, "known: char", cfg.utility_bar.button_large,
        cfg.utility_bar.button_height)
    filterBtn:SetPoint("LEFT", buybackBtn, "RIGHT", 5, 0)
    update_filter_button_style(filterBtn)

    filterBtn:SetScript("OnClick", function(self)
        if sfui.merchant.filterKnown == 1 or sfui.merchant.filterKnown == true then
            sfui.merchant.filterKnown = 2
        elseif sfui.merchant.filterKnown == 2 then
            sfui.merchant.filterKnown = 0
        else
            sfui.merchant.filterKnown = 1
        end
        update_filter_button_style(self)
        sfui.merchant.reset_scroll_and_rebuild()
    end)

    filterBtn:SetScript("OnEnter", function(self)
        if not sfui.merchant.filterKnown or sfui.merchant.filterKnown == 0 then
            common.set_color(self, cfg.button_colors.filter_hover)
        end
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("known items filter", 1, 1, 1)
            if sfui.merchant.filterKnown == 2 then
                GameTooltip:AddLine("currently hiding all recipes and items known by any alt.", 0.2, 0.8, 1, true)
                GameTooltip:AddLine("click to show all items.", 0.7, 0.7, 0.7)
            elseif sfui.merchant.filterKnown == 1 or sfui.merchant.filterKnown == true then
                GameTooltip:AddLine("currently hiding recipes and items known by this character.", 0.2, 1, 0.4, true)
                GameTooltip:AddLine("click to hide recipes known across your warband.", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("currently showing all items.", 1, 1, 1, true)
                GameTooltip:AddLine("click to hide recipes and items known by this character.", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end
    end)

    filterBtn:SetScript("OnLeave", function(self)
        update_filter_button_style(self)
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end)
    sfui.merchant.filterBtn = filterBtn

    -- Guild repair button
    local guildRepairBtn = CreateFrame("Button", nil, utilityBar, "BackdropTemplate")
    guildRepairBtn:SetSize(22, 22)
    guildRepairBtn:SetPoint("RIGHT", 0, 0)
    local grIcon = guildRepairBtn:CreateTexture(nil, "ARTWORK")
    grIcon:SetAllPoints()
    grIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02") -- Coin icon
    grIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    guildRepairBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local repairAllCost, canRepair = GetRepairAllCost()

        if canRepair and (issecretvalue(repairAllCost) or (repairAllCost and repairAllCost > 0)) then
            common.SafeSetTooltipMoney(GameTooltip, repairAllCost, "Guild Repair")

            local amount = GetGuildBankMoney()
            local withdrawLimit = GetGuildBankWithdrawMoney()
            local isSecretAmount = issecretvalue(amount)

            if not isSecretAmount and withdrawLimit >= 0 then
                amount = math.min(amount, withdrawLimit)
            end

            common.SafeAddMoneyLine(GameTooltip, "Guild Funds: ", amount)
        else
            GameTooltip:SetText("no repair needed")
        end
        GameTooltip:Show()
    end)
    guildRepairBtn:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end)
    guildRepairBtn:SetScript("OnClick", function()
        if CanMerchantRepair() and CanGuildBankRepair() then
            RepairAllItems(true)
            grIcon:SetDesaturated(true)
        end
    end)

    -- Personal repair button
    local repairBtn = CreateFrame("Button", nil, utilityBar, "BackdropTemplate")
    repairBtn:SetSize(22, 22)
    repairBtn:SetPoint("RIGHT", guildRepairBtn, "LEFT", -5, 0)
    local rIcon = repairBtn:CreateTexture(nil, "ARTWORK")
    rIcon:SetAllPoints()
    rIcon:SetTexture("Interface\\Icons\\Trade_BlackSmithing") -- Anvil/Hammer
    rIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    repairBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local repairAllCost, canRepair = GetRepairAllCost()
        local isSecret = issecretvalue(repairAllCost)

        if canRepair and (isSecret or (repairAllCost and repairAllCost > 0)) then
            common.SafeSetTooltipMoney(GameTooltip, repairAllCost, "Repair All")
        else
            GameTooltip:SetText("no repair needed")
        end
        GameTooltip:Show()
    end)
    repairBtn:SetScript("OnLeave", function()
        if GameTooltip and GameTooltip:IsShown() then
            GameTooltip:Hide()
        end
    end)
    repairBtn:SetScript("OnClick", function()
        if CanMerchantRepair() then
            RepairAllItems(false)
            rIcon:SetDesaturated(true)
        end
    end)

    -- Sell junk button
    local sellJunkBtn = CreateFlatButton(utilityBar, "sell greys", cfg.utility_bar.button_medium,
        cfg.utility_bar.button_height)
    sellJunkBtn:SetPoint("RIGHT", repairBtn, "LEFT", -5, 0)

    sellJunkBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("sell all greys")
        GameTooltip:Show()
    end)
    sellJunkBtn:HookScript("OnLeave", GameTooltip_Hide)
    sellJunkBtn:SetScript("OnClick", function()
        local totalPrice = 0
        common.for_each_bag_item(function(bag, slot, itemID, link, info)
            if info and (link or info.hyperlink) and info.quality == 0 then
                local price = info.noValue and 0 or (select(11, sfui.common.get_item_info(link or info.hyperlink)) or 0)
                if price > 0 then
                    totalPrice = totalPrice + (price * (info.stackCount or 1))
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end)
        if totalPrice > 0 then
            common.print("|cff00ff00sold greys for " .. common.SafeGetCoinTextureString(totalPrice) .. ".|r")
        else
            common.print("|cffff0000no greys to sell.|r")
        end
    end)

    local function update_repair_buttons()
        local canRepair = CanMerchantRepair()
        local repairAllCost, canRepairItems = GetRepairAllCost()
        local needsRepair = canRepairItems and repairAllCost > 0

        if canRepair and needsRepair and CanGuildBankRepair() then
            grIcon:SetDesaturated(false)
            guildRepairBtn:Enable()
        else
            grIcon:SetDesaturated(true)
            guildRepairBtn:Disable()
        end

        if canRepair and needsRepair then
            rIcon:SetDesaturated(false)
            repairBtn:Enable()
        else
            rIcon:SetDesaturated(true)
            repairBtn:Disable()
        end
    end

    sfui.merchant.update_repair_buttons = update_repair_buttons
    sfui.events.RegisterEvent("UPDATE_INVENTORY_DURABILITY", update_repair_buttons)
    sfui.events.RegisterEvent("MERCHANT_SHOW",               update_repair_buttons)

    return utilityBar
end
