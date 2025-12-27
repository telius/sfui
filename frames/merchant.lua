---@diagnostic disable: undefined-global
-- frames/merchant.lua
-- Custom 4x7 grid merchant frame for sfui

sfui = sfui or {}
sfui.merchant = {}

-- Cache color references
local colors = sfui.config.colors

local MSQ = LibStub and LibStub("Masque", true)
local msqGroup
if MSQ then
    msqGroup = MSQ:Group("Sfui", "Merchant")
end

local NUM_ROWS = 7
local NUM_COLS = 4
local ITEMS_PER_PAGE = NUM_ROWS * NUM_COLS -- 28

local frame = CreateFrame("Frame", "SfuiMerchantFrame", UIParent, "BackdropTemplate")
frame:SetSize(NUM_COLS * 200 + 40, NUM_ROWS * 50 + 100) -- Increased height
frame:SetPoint("CENTER")
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = nil,
    tile = true,
    tileSize = 32,
    edgeSize = 0,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
})
frame:SetBackdropColor(0, 0, 0, 0.7)
frame:Hide()
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
sfui.merchant.frame = frame

-- Portrait
frame.portrait = frame:CreateTexture(nil, "OVERLAY")
frame.portrait:SetSize(60, 60)
frame.portrait:SetPoint("TOPLEFT", 10, 30) -- Half outside (top is y=0, so y=30 is 30px UP)

-- Name & Title
frame.merchantName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.merchantName:SetPoint("TOPLEFT", frame, "TOPLEFT", 80, -4) -- 4p below top
frame.merchantName:SetJustifyH("LEFT")

frame.merchantTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.merchantTitle:SetPoint("TOPLEFT", frame.merchantName, "BOTTOMLEFT", 0, -2)
frame.merchantTitle:SetJustifyH("LEFT")

-- Helper for Flat Buttons
local CreateFlatButton = sfui.common.CreateFlatButton

-- Close Button
local closeBtn = CreateFlatButton(frame, "X", 20, 20)
closeBtn:SetPoint("TOPRIGHT", -5, -5)
closeBtn:SetScript("OnClick", function()
    frame:Hide()
end)



-- Filter Dropdown
local filterDropdownBtn = CreateFlatButton(frame, "showing all", 100, 20)
filterDropdownBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
filterDropdownBtn:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
        rootDescription:SetTag("MENU_MERCHANT_FILTER");

        rootDescription:CreateButton("All Items", function()
            SetMerchantFilter(LE_LOOT_FILTER_ALL)
            self:SetText("showing all")
            sfui.merchant.BuildItemList()
        end);
        rootDescription:CreateButton("Current Class", function()
            SetMerchantFilter(LE_LOOT_FILTER_CLASS)
            self:SetText("current class")
            sfui.merchant.BuildItemList()
        end);
        rootDescription:CreateButton("Current Specialization", function()
            SetMerchantFilter(LE_LOOT_FILTER_SPEC)
            self:SetText("current spec")
            sfui.merchant.BuildItemList()
        end);
    end);
end)

-- Settings Dropdown
local settingsDropdownBtn = CreateFlatButton(frame, "settings", 70, 20)
settingsDropdownBtn:SetPoint("RIGHT", filterDropdownBtn, "LEFT", -5, 0)
settingsDropdownBtn:SetScript("OnClick", function(self)
    MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
        rootDescription:SetTag("MENU_MERCHANT_SETTINGS");

        rootDescription:CreateCheckbox("Auto-Sell Greys",
            function() return SfuiDB.autoSellGreys end,
            function()
                SfuiDB.autoSellGreys = not SfuiDB.autoSellGreys
            end);

        rootDescription:CreateCheckbox("Auto-Repair",
            function() return SfuiDB.autoRepair end,
            function()
                SfuiDB.autoRepair = not SfuiDB.autoRepair
            end);
    end);
end)

-- Scroll Variables
local scrollOffset = 0
local totalMerchantItems = 0

-- Housing Decor Filter State: 0 = show all, 1 = hide owned, 2 = hide if any in storage
sfui.merchant.housingDecorFilter = sfui.merchant.housingDecorFilter or 0

-- Track if current merchant is a decor vendor
local isDecorVendor = false

-- Item Buttons Array
local buttons = {}

-- Create the stack split dialog frame
function sfui.merchant.CreateStackSplitFrame(parent)
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
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("TOP", 0, -8)
    f.title:SetText("Enter Quantity")

    -- EditBox
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetSize(80, 24)
    eb:SetPoint("TOP", 0, -30)
    eb:SetFontObject("ChatFontNormal")
    eb:SetJustifyH("CENTER")
    eb:SetNumeric(true)
    eb:SetAutoFocus(true)

    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)

    eb:SetScript("OnEnterPressed", function() f.buyBtn:Click() end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.editBox = eb

    -- Max Button
    f.maxBtn = sfui.common.CreateFlatButton(f, "Max", 40, 24)
    f.maxBtn:SetPoint("LEFT", eb, "RIGHT", 5, 0)
    sfui.common.SetColor(f.maxBtn, "black")
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

    -- Buy Button
    f.buyBtn = sfui.common.CreateFlatButton(f, "Buy", 70, 24)
    f.buyBtn:SetPoint("BOTTOMLEFT", 10, 10)
    sfui.common.SetColor(f.buyBtn, "black")
    f.buyBtn:SetScript("OnClick", function()
        local val = tonumber(eb:GetText()) or 1
        if val > 0 then
            BuyMerchantItem(f.index, val)
        end
        f:Hide()
    end)

    -- Cancel Button
    f.cancelBtn = sfui.common.CreateFlatButton(f, "Cancel", 70, 24)
    f.cancelBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    sfui.common.SetColor(f.cancelBtn, "black")
    f.cancelBtn:SetScript("OnClick", function() f:Hide() end)

    return f
end

local function OpenStackSplit(index)
    if not sfui.merchant.stackSplitFrame then
        sfui.merchant.stackSplitFrame = sfui.merchant.CreateStackSplitFrame(sfui.merchant.frame)
    end

    local f = sfui.merchant.stackSplitFrame
    f.index = index
    f.editBox:SetText("1")

    local info = C_MerchantFrame.GetItemInfo(index)
    local name, price, stackCount
    if info then
        name = info.name
        price = info.price
        stackCount = info.stackCount
    end
    local link = GetMerchantItemLink(index)
    if link then
        local _, _, _, _, _, _, _, itemStackCount = C_Item.GetItemInfo(link)
        f.maxStack = itemStackCount
    else
        f.maxStack = 9999
    end
    f.price = price
    f.stackCount = stackCount -- Amount received per buy

    f:Show()
    f.editBox:SetFocus()
end

-- Create Item Button
function sfui.merchant.CreateItemButton(id, parent, msqGroup)
    local btn = CreateFrame("Button", "SfuiMerchantItem" .. id, parent, "BackdropTemplate")
    btn:SetSize(190, 45)

    -- Icon Wrap (for Masque)
    local iconWrap = CreateFrame("Button", nil, btn, "BackdropTemplate")
    iconWrap:SetSize(40, 40)
    iconWrap:SetPoint("LEFT", 2, 0)
    iconWrap:EnableMouse(false) -- Allow clicks to pass to parent row
    btn.iconWrap = iconWrap

    -- Icon
    btn.icon = iconWrap:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints(iconWrap)

    -- Name
    btn.nameStub = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameStub:SetPoint("TOPLEFT", iconWrap, "TOPRIGHT", 5, 2)
    btn.nameStub:SetJustifyH("LEFT")

    -- SubType (below Name)
    btn.subName = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.subName:SetPoint("TOPLEFT", btn.nameStub, "BOTTOMLEFT", 0, -1)
    btn.subName:SetJustifyH("LEFT")
    btn.subName:SetTextColor(0.6, 0.6, 0.6) -- Grey

    -- Price
    btn.price = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.price:SetPoint("BOTTOMLEFT", iconWrap, "BOTTOMRIGHT", 5, 0)
    btn.price:SetJustifyH("LEFT")

    -- Count (stack size)
    btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    btn.count:SetPoint("BOTTOMRIGHT", iconWrap, -2, 2)

    -- Highlight
    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.link then
            GameTooltip:SetHyperlink(self.link)
        elseif self.hasItem then
            GameTooltip:SetMerchantItem(self:GetID())
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    btn:SetScript("OnClick", function(self, button)
        if self.hasItem then
            if sfui.merchant.mode == "buyback" then
                BuybackItem(self:GetID())
            else
                -- Merchant
                if IsControlKeyDown() and button == "RightButton" then
                    if self.link then
                        DressUpLink(self.link)
                    end
                    return
                end

                if IsShiftKeyDown() and button == "RightButton" then
                    OpenStackSplit(self:GetID())
                    return
                end

                if button == "RightButton" then
                    BuyMerchantItem(self:GetID())
                else
                    PickupMerchantItem(self:GetID())
                end
            end
        end
    end)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if msqGroup then
        msqGroup:AddButton(iconWrap, { Icon = btn.icon })
    end

    return btn
end

-- Create Button Grid
for i = 1, ITEMS_PER_PAGE do
    local btn = sfui.merchant.CreateItemButton(i, frame, msqGroup)
    local row = math.floor((i - 1) / NUM_COLS)
    local col = (i - 1) % NUM_COLS

    btn:SetPoint("TOPLEFT", 20 + (col * 195), -40 - (row * 50))
    buttons[i] = btn
end

-- Scroll Bar
local scrollBar = CreateFrame("Slider", nil, frame, "BackdropTemplate")
scrollBar:SetOrientation("HORIZONTAL")
scrollBar:SetPoint("BOTTOMLEFT", 15, 35) -- Above currency frame
scrollBar:SetPoint("BOTTOMRIGHT", -15, 35)
scrollBar:SetHeight(6)
scrollBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
})
scrollBar:SetBackdropColor(0, 0, 0, 0.3)
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)
scrollBar:SetScript("OnValueChanged", function(self, value)
    local newOffset = math.floor(value)

    if scrollOffset ~= newOffset then
        scrollOffset = newOffset
        sfui.merchant.UpdateMerchant()
    end
end)

local thumb = scrollBar:CreateTexture(nil, "ARTWORK")
thumb:SetSize(30, 6)
thumb:SetColorTexture(1, 1, 1, 1) -- Flat white
scrollBar:SetThumbTexture(thumb)
frame.scrollBar = scrollBar



-- Update Currency Display
function sfui.merchant.UpdateCurrencyDisplay(frame)
    frame.currencyDisplays = frame.currencyDisplays or {}
    local displays = frame.currencyDisplays

    -- Hide old
    for _, f in pairs(displays) do f:Hide() end

    local cache = sfui.merchant.currencyCache or {}

    -- Sort currencies by name for stability
    local sorted = {}
    for name, data in pairs(cache) do
        table.insert(sorted, { name = name, data = data })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    if #sorted == 0 then return end

    -- Create Container if needed
    if not frame.currencyContainer then
        frame.currencyContainer = CreateFrame("Frame", nil, frame)
        frame.currencyContainer:SetHeight(20)
        -- Anchored to BOTTOM center of frame
        frame.currencyContainer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    end
    local container = frame.currencyContainer
    container:Show()

    local activeDisplays = {}
    local totalWidth = 0

    for i, item in ipairs(sorted) do
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

            displays[idx] = display
        end

        display.icon:SetTexture(data.texture)

        -- Format all currencies with K/M
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

    -- Update Container Width and Layout
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

sfui.merchant.mode = "merchant" -- "merchant" or "buyback"
sfui.merchant.filterKnown = true

local utilityBar = CreateFrame("Frame", nil, frame)
utilityBar:SetHeight(30)
utilityBar:SetPoint("BOTTOMLEFT", 10, 2)
utilityBar:SetPoint("BOTTOMRIGHT", -10, 2)

-- Buyback Toggle
local buybackBtn = CreateFlatButton(utilityBar, "buyback", 100, 22)
buybackBtn:SetPoint("LEFT", 0, 0)
buybackBtn:SetScript("OnClick", function(self)
    if sfui.merchant.mode == "merchant" then
        sfui.merchant.mode = "buyback"
        self:SetText("merchant")
    else
        sfui.merchant.mode = "merchant"
        self:SetText("buyback")
    end
    scrollOffset = 0
    frame.scrollBar:SetValue(0)
    sfui.merchant.BuildItemList()
end)

-- Hide Known Toggle
local filterBtn = CreateFlatButton(utilityBar, "hide known", 100, 22)
filterBtn:SetPoint("LEFT", buybackBtn, "RIGHT", 5, 0)
-- UpdateFilterButtonStyle moved up or called after definition
-- Better to define function first then create button? Or just define function then call it.

local function UpdateFilterButtonStyle(self)
    if sfui.merchant.filterKnown then
        self:SetText("hiding known")
        self:SetBackdropBorderColor(0.4, 0, 1, 1)    -- Purple (#6600FF)
        self:GetFontString():SetTextColor(0.4, 0, 1) -- Purple
    else
        self:SetText("showing known")
        self:SetBackdropBorderColor(1, 1, 1, 1)    -- White
        self:GetFontString():SetTextColor(1, 1, 1) -- White
    end
end
UpdateFilterButtonStyle(filterBtn)

filterBtn:SetScript("OnClick", function(self)
    sfui.merchant.filterKnown = not sfui.merchant.filterKnown
    UpdateFilterButtonStyle(self)
    scrollOffset = 0
    frame.scrollBar:SetValue(0)
    sfui.merchant.BuildItemList()
end)

filterBtn:SetScript("OnEnter", function(self)
    if not sfui.merchant.filterKnown then
        self:GetFontString():SetTextColor(0, 1, 1, 1) -- Cyan hover if not active
        self:SetBackdropBorderColor(0, 1, 1, 1)       -- Cyan (#00FFFF)
    end
end)


filterBtn:SetScript("OnLeave", function(self)
    UpdateFilterButtonStyle(self) -- Revert to state color
end)

-- Housing Decor Filter Button
local housingFilterBtn = CreateFlatButton(utilityBar, "decor: all", 100, 22)
housingFilterBtn:SetPoint("LEFT", filterBtn, "RIGHT", 5, 0)

local function UpdateHousingFilterButtonStyle(self)
    if sfui.merchant.housingDecorFilter == 1 then
        self:SetText("decor: hide owned")
        self:SetBackdropBorderColor(1, 0, 1, 1)    -- Magenta (#FF00FF)
        self:GetFontString():SetTextColor(1, 0, 1) -- Magenta
    elseif sfui.merchant.housingDecorFilter == 2 then
        self:SetText("decor: hide storage")
        self:SetBackdropBorderColor(0.4, 0, 1, 1)    -- Purple (#6600FF)
        self:GetFontString():SetTextColor(0.4, 0, 1) -- Purple
    else
        self:SetText("decor: show all")
        self:SetBackdropBorderColor(1, 1, 1, 1)    -- White
        self:GetFontString():SetTextColor(1, 1, 1) -- White
    end
end
UpdateHousingFilterButtonStyle(housingFilterBtn)

housingFilterBtn:SetScript("OnClick", function(self)
    -- Cycle through states: 0 -> 1 -> 2 -> 0
    sfui.merchant.housingDecorFilter = (sfui.merchant.housingDecorFilter + 1) % 3
    UpdateHousingFilterButtonStyle(self)
    scrollOffset = 0
    frame.scrollBar:SetValue(0)
    sfui.merchant.BuildItemList()
end)

housingFilterBtn:SetScript("OnEnter", function(self)
    if sfui.merchant.housingDecorFilter == 0 then
        self:GetFontString():SetTextColor(0, 1, 1, 1) -- Cyan hover if showing all
        self:SetBackdropBorderColor(0, 1, 1, 1)       -- Cyan (#00FFFF)
    end
end)

housingFilterBtn:SetScript("OnLeave", function(self)
    UpdateHousingFilterButtonStyle(self) -- Revert to state color
end)

-- Guild Repair
local guildRepairBtn = CreateFrame("Button", nil, utilityBar, "BackdropTemplate")
guildRepairBtn:SetSize(22, 22)
guildRepairBtn:SetPoint("RIGHT", 0, 0)
local grIcon = guildRepairBtn:CreateTexture(nil, "ARTWORK")
grIcon:SetAllPoints()
grIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02") -- Coin icon
grIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
guildRepairBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local repairAllCost, canRepair = GetRepairAllCost()
    if canRepair and repairAllCost > 0 then
        GameTooltip:SetText("Guild Repair")
        SetTooltipMoney(GameTooltip, repairAllCost)
        local amount = GetGuildBankMoney()
        local withdrawLimit = GetGuildBankWithdrawMoney()
        if withdrawLimit >= 0 then
            amount = math.min(amount, withdrawLimit)
        end
        GameTooltip:AddLine("Guild Funds: " .. GetCoinTextureString(amount), 1, 1, 1)
    else
        GameTooltip:SetText("No Repair Needed")
    end
    GameTooltip:Show()
end)
guildRepairBtn:SetScript("OnLeave", GameTooltip_Hide)
guildRepairBtn:SetScript("OnClick", function()
    if CanMerchantRepair() and CanGuildBankRepair() then
        RepairAllItems(true)
        grIcon:SetDesaturated(true) -- Temp feedback
    end
end)

-- Repair All
local repairBtn = CreateFrame("Button", nil, utilityBar, "BackdropTemplate")
repairBtn:SetSize(22, 22)
repairBtn:SetPoint("RIGHT", guildRepairBtn, "LEFT", -5, 0)
local rIcon = repairBtn:CreateTexture(nil, "ARTWORK")
rIcon:SetAllPoints()
rIcon:SetTexture("Interface\\Icons\\Trade_BlackSmithing") -- Anvil/Hammer
rIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
repairBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local repairAllCost, canRepair = GetRepairAllCost()
    if canRepair and repairAllCost > 0 then
        GameTooltip:SetText("Repair All")
        SetTooltipMoney(GameTooltip, repairAllCost)
    else
        GameTooltip:SetText("No Repair Needed")
    end
    GameTooltip:Show()
end)
repairBtn:SetScript("OnLeave", GameTooltip_Hide)
repairBtn:SetScript("OnClick", function()
    if CanMerchantRepair() then
        RepairAllItems(false)
        rIcon:SetDesaturated(true)
    end
end)

-- Sell Greys
local sellJunkBtn = CreateFlatButton(utilityBar, "sell greys", 80, 22)
sellJunkBtn:SetPoint("RIGHT", repairBtn, "LEFT", -5, 0)

sellJunkBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Sell All Greys")
    GameTooltip:Show()
end)
sellJunkBtn:HookScript("OnLeave", GameTooltip_Hide)
sellJunkBtn:SetScript("OnClick", function()
    local totalPrice = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and info.quality == 0 then
                local price = info.noValue and 0 or (select(11, C_Item.GetItemInfo(info.hyperlink)) or 0)
                if price > 0 then
                    totalPrice = totalPrice + (price * info.stackCount)
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end
    if totalPrice > 0 then
        print("|cff00ff00Sold greys for " .. C_CurrencyInfo.GetCoinTextureString(totalPrice) .. ".|r")
    else
        print("|cffff0000No greys to sell.|r")
    end
end)

-- Auto-Sell Greys Function
local function AutoSellGreys()
    if not SfuiDB.autoSellGreys then return end

    local totalPrice = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and info.quality == 0 then
                local price = info.noValue and 0 or (select(11, C_Item.GetItemInfo(info.hyperlink)) or 0)
                if price > 0 then
                    totalPrice = totalPrice + (price * info.stackCount)
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end
    if totalPrice > 0 then
        print("|cff00ff00Auto-sold greys for " .. C_CurrencyInfo.GetCoinTextureString(totalPrice) .. ".|r")
    end
end

-- Auto-Repair Function
local function AutoRepair()
    if not SfuiDB.autoRepair then return end
    if not CanMerchantRepair() then return end

    -- Check for blacksmith master hammers (current expansion only)
    -- TWW: 225660, Midnight: 238020
    local hasBlacksmithHammer = C_Item.GetItemCount(225660) > 0 or C_Item.GetItemCount(238020) > 0
    if hasBlacksmithHammer then
        print("|cffff9900Auto-repair skipped: Blacksmith hammer detected.|r")
        return
    end

    local repairAllCost, canRepair = GetRepairAllCost()
    if not canRepair or repairAllCost == 0 then return end

    -- Try guild repair first
    if CanGuildBankRepair() then
        RepairAllItems(true)
        print("|cff00ff00Auto-repaired using guild funds for " ..
            C_CurrencyInfo.GetCoinTextureString(repairAllCost) .. ".|r")
    else
        RepairAllItems(false)
        print("|cff00ff00Auto-repaired for " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost) .. ".|r")
    end
end


-- Event to update repair status
local function UpdateRepairButtons()
    local canRepair = CanMerchantRepair()
    local repairAllCost, canRepairItems = GetRepairAllCost()
    local needsRepair = canRepairItems and repairAllCost > 0

    -- Repair
    if canRepair and needsRepair then
        rIcon:SetDesaturated(false)
        repairBtn:Enable()
    else
        rIcon:SetDesaturated(true)
        repairBtn:Disable()
    end

    -- Guild Repair
    if canRepair and needsRepair and CanGuildBankRepair() then
        grIcon:SetDesaturated(false)
        guildRepairBtn:Enable()
    else
        grIcon:SetDesaturated(true)
        guildRepairBtn:Disable()
    end
end

frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
frame:HookScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" or event == "UPDATE_INVENTORY_DURABILITY" then
        UpdateRepairButtons()
    end
end)


sfui.merchant.filteredIndices = {}

sfui.merchant.currencyCache = {}

sfui.merchant.BuildItemList = function()
    local numItemsRaw = 0
    if sfui.merchant.mode == "buyback" then
        numItemsRaw = GetNumBuybackItems()
    else
        numItemsRaw = GetMerchantNumItems()
    end

    sfui.merchant.filteredIndices = {}
    sfui.merchant.currencyCache = {}

    for i = 1, numItemsRaw do
        local include = true
        if sfui.merchant.mode == "merchant" and sfui.merchant.filterKnown then
            local link = GetMerchantItemLink(i)
            if sfui.common.IsItemKnown(link) then
                include = false
            end

            -- Battle Pet Check
            if include and link then
                local itemID = GetItemInfoFromHyperlink(link)
                if itemID then
                    -- GetPetInfoByItemID returns: ..., speciesID (13th return)
                    local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
                    if speciesID then
                        local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
                        if numCollected and numCollected > 0 then
                            include = false
                        end
                    end
                end
            end
        end

        -- Housing Decor Filter
        if include and sfui.merchant.mode == "merchant" and sfui.merchant.housingDecorFilter > 0 then
            local link = GetMerchantItemLink(i)
            if link then
                local housingInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem and
                    C_HousingCatalog.GetCatalogEntryInfoByItem(link, true)

                if housingInfo then
                    local function isValidCount(value)
                        return value and value > 0 and value < 4294967295
                    end

                    if sfui.merchant.housingDecorFilter == 1 then
                        -- Hide if owned (any quantity or placed)
                        if isValidCount(housingInfo.quantity) or isValidCount(housingInfo.numPlaced) or
                            isValidCount(housingInfo.remainingRedeemable) then
                            include = false
                        end
                    elseif sfui.merchant.housingDecorFilter == 2 then
                        -- Hide if any in storage
                        if isValidCount(housingInfo.quantity) then
                            include = false
                        end
                    end
                end
            end
        end

        if include then
            table.insert(sfui.merchant.filteredIndices, i)
        end

        -- Currency Scanning (Merged Loop)
        if sfui.merchant.mode == "merchant" then
            local itemInfo = C_MerchantFrame.GetItemInfo(i)
            if itemInfo then
                -- Check if item costs gold
                if itemInfo.price and itemInfo.price > 0 then
                    if not sfui.merchant.currencyCache["Gold"] then
                        local goldAmount = math.floor(GetMoney() / 10000) -- Convert copper to gold, rounded down
                        sfui.merchant.currencyCache["Gold"] = {
                            texture = 133784,                             -- Gold coin icon
                            count = goldAmount
                        }
                    end
                end

                -- Check simple currencyID first (API 12.0)
                if itemInfo.currencyID then
                    local info = C_CurrencyInfo.GetCurrencyInfo(itemInfo.currencyID)
                    if info then
                        if not sfui.merchant.currencyCache[info.name] then
                            sfui.merchant.currencyCache[info.name] = { texture = info.iconFileID, count = info.quantity }
                        end
                    end
                end

                -- Check extended costs (multiple currencies/items)
                if itemInfo.hasExtendedCost then
                    local itemCount = GetMerchantItemCostInfo(i)
                    if itemCount and itemCount > 0 then
                        for j = 1, itemCount do
                            local texture, amount, link, currencyName = GetMerchantItemCostItem(i, j)
                            if currencyName and amount then
                                if not sfui.merchant.currencyCache[currencyName] then
                                    local count = 0
                                    local currencyID = link and string.match(link, "currency:(%d+)")
                                    if currencyID then
                                        local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(currencyID))
                                        if info then count = info.quantity end
                                    else
                                        count = C_Item.GetItemCount(link)
                                    end
                                    sfui.merchant.currencyCache[currencyName] = { texture = texture, count = count }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Detect if vendor sells housing decor items
    local hasHousingDecor = false
    if sfui.merchant.mode == "merchant" and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
        for i = 1, numItemsRaw do
            local link = GetMerchantItemLink(i)
            if link then
                local housingInfo = C_HousingCatalog.GetCatalogEntryInfoByItem(link, true)
                if housingInfo then
                    hasHousingDecor = true
                    break
                end
            end
        end
    end

    -- Show/hide housing filter button based on whether vendor sells housing decor
    if housingFilterBtn then
        if hasHousingDecor then
            housingFilterBtn:Show()
        else
            housingFilterBtn:Hide()
        end
    end

    totalMerchantItems = #sfui.merchant.filteredIndices

    -- Setup ScrollBar Max
    local maxOffset = math.max(0, totalMerchantItems - ITEMS_PER_PAGE)
    frame.scrollBar:SetMinMaxValues(0, maxOffset)
    frame.scrollBar:SetValueStep(1)

    -- Hide scrollbar if not needed
    if maxOffset > 0 then
        frame.scrollBar:Show()
    else
        frame.scrollBar:Hide()
    end

    -- Update Display
    sfui.merchant.UpdateMerchant()
    sfui.merchant.UpdateCurrencyDisplay(frame) -- Now uses cache
end

sfui.merchant.UpdateMerchant = function()
    local filteredIndices = sfui.merchant.filteredIndices or {}
    local numItems = #filteredIndices

    local itemInfo
    for i = 1, ITEMS_PER_PAGE do
        local btn = buttons[i]
        local displayIndex = scrollOffset + i
        local realIndex = filteredIndices[displayIndex]

        if realIndex then
            local index = realIndex
            -- Branching Logic for Data Retrieval
            local data = {}
            if sfui.merchant.mode == "buyback" then
                local name, texture, price, quantity, numAvailable, isUsable = GetBuybackItemInfo(index)
                if name then
                    data.name = name
                    data.texture = texture
                    data.price = price
                    data.stackCount = quantity
                    data.isUsable = isUsable
                    data.hasExtendedCost = false -- Buyback is always gold

                    local link = GetBuybackItemLink(index)
                    if link then
                        local _, _, quality, _, _, _, itemSubType, _, itemEquipLoc, _, _, classID, subClassID = C_Item
                            .GetItemInfo(link)
                        data.quality = quality
                        data.subType = itemSubType
                        data.equipLoc = itemEquipLoc
                        data.classID = classID
                        data.subClassID = subClassID
                        btn.link = link
                    end
                end
            else
                local info = C_MerchantFrame.GetItemInfo(index)
                if info then
                    data = info -- Compatible structure
                    local link = GetMerchantItemLink(index)
                    btn.link = link
                    if link then
                        local _, _, quality, _, _, _, itemSubType, _, itemEquipLoc, _, _, classID, subClassID = C_Item
                            .GetItemInfo(link)
                        data.quality = quality
                        data.subType = itemSubType
                        data.equipLoc = itemEquipLoc
                        data.classID = classID
                        data.subClassID = subClassID
                    end
                end
            end

            if data.name then
                btn:SetID(index)
                btn.hasItem = true
                btn.icon:SetTexture(data.texture)

                -- Item Type Display or Housing Decor Info
                local typeText = ""

                -- Check if this is a housing decor item (Decor vendor OR item is Decor type)
                -- We check subType "Decor" or "Housing" to catch items on general vendors
                local isDecorItem = data.subType and
                    (string.find(data.subType, "Decor") or string.find(data.subType, "Housing"))
                local shouldQuery = isDecorVendor or isDecorItem

                if shouldQuery then
                    -- 1. Try Live API
                    local housingInfo = C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem and
                        btn.link and C_HousingCatalog.GetCatalogEntryInfoByItem(btn.link, true)

                    local totalOwned, placed, storage = 0, 0, 0
                    local hasData = false

                    -- Helper to validate values
                    local function isValidCount(value)
                        return value and value >= 0 and value < 4294967000
                    end

                    if housingInfo then
                        -- Sanitize values to prevent integer overflow (UINT_MAX)
                        local rawQty = housingInfo.quantity
                        local rawRedeem = housingInfo.remainingRedeemable
                        local rawPlaced = housingInfo.numPlaced

                        local qty = isValidCount(rawQty) and rawQty or 0
                        local redeem = isValidCount(rawRedeem) and rawRedeem or 0
                        local numsPlaced = isValidCount(rawPlaced) and rawPlaced or 0

                        totalOwned = qty + redeem
                        placed = numsPlaced
                        storage = qty

                        -- Update Cache (only if we have valid, non-zero data to save)
                        if SfuiDecorDB and SfuiDecorDB.items and btn.link then
                            local itemID = C_Item.GetItemInfoInstant(btn.link)
                            if not itemID then
                                itemID = tonumber(string.match(btn.link, "item:(%d+)"))
                            end

                            if itemID then
                                -- Save even if 0, so we know we checked it
                                SfuiDecorDB.items[itemID] = { o = totalOwned, p = placed, s = storage }
                            end
                        end
                        hasData = true
                    else
                        -- 2. Fallback to Cache
                        -- use robust ID extraction
                        local itemID = C_Item.GetItemInfoInstant(btn.link)
                        if not itemID then
                            itemID = tonumber(string.match(btn.link, "item:(%d+)"))
                        end

                        if SfuiDecorDB and SfuiDecorDB.items and itemID then
                            local cached = SfuiDecorDB.items[itemID]
                            if cached then
                                totalOwned = cached.o or 0
                                placed = cached.p or 0
                                storage = cached.s or 0
                                hasData = true
                            end
                        end
                    end

                    -- 3. Construct Display String
                    local parts = {}
                    if hasData then
                        -- Always show 'o' if we have data, even if 0
                        local oStr = "o:" .. math.max(0, totalOwned)
                        table.insert(parts, oStr)

                        if isValidCount(placed) and placed > 0 then
                            table.insert(parts, "p:" .. placed)
                        end
                        if isValidCount(storage) and storage > 0 then
                            table.insert(parts, "s:" .. storage)
                        end
                    end

                    if #parts > 0 then
                        typeText = table.concat(parts, " ")
                    else
                        -- Fallback only if strictly NO data (nil housingInfo AND nil cache)
                        -- Or if for some reason hasData is true but parts is empty (shouldn't happen with change above)
                        local slotText = (data.equipLoc and data.equipLoc ~= "" and _G[data.equipLoc]) or ""
                        local subTypeText = data.subType or ""

                        if slotText ~= "" then
                            typeText = slotText
                        elseif subTypeText ~= "" then
                            typeText = subTypeText
                        end
                    end
                else
                    -- Regular item type display
                    local slotText = (data.equipLoc and data.equipLoc ~= "" and _G[data.equipLoc]) or ""
                    local subTypeText = data.subType or ""

                    if slotText ~= "" then
                        typeText = slotText
                        -- Only append Armor Type for Cloth(1), Leather(2), Mail(3), Plate(4)
                        -- Item Class 4 is Armor
                        if data.classID == 4 and data.subClassID and (data.subClassID >= 1 and data.subClassID <= 4) then
                            if subTypeText ~= slotText then
                                typeText = typeText .. " - " .. subTypeText
                            end
                        end
                    else
                        typeText = subTypeText
                    end
                    if typeText == "Other" then typeText = "" end
                end
                btn.subName:SetText(typeText)

                -- Rarity Color
                if data.quality then
                    local r, g, b = C_Item.GetItemQualityColor(data.quality)
                    btn.nameStub:SetTextColor(r, g, b, 1)
                else
                    btn.nameStub:SetTextColor(1, 1, 1, 1)
                end

                -- Truncation Logic
                local maxWidth = 135
                local text = data.name
                btn.nameStub:SetText(text)

                if btn.nameStub:GetStringWidth() > maxWidth then
                    local words = {}
                    for w in string.gmatch(text, "%S+") do table.insert(words, w) end

                    if #words >= 2 then
                        -- Keep only the last 2 words
                        text = "... " .. words[#words - 1] .. " " .. words[#words]
                        btn.nameStub:SetText(text)
                    end
                end

                -- Cost Logic
                local costString = ""
                if data.price > 0 then
                    local color = "|cffffffff" -- White
                    if GetMoney() < data.price then
                        color = "|cffff0000"   -- Red
                    end
                    costString = color .. C_CurrencyInfo.GetCoinTextureString(data.price) .. "|r"
                end

                if data.hasExtendedCost then
                    local count = GetMerchantItemCostInfo(index)
                    if count then
                        for i = 1, count do
                            local texture, value, link, name = GetMerchantItemCostItem(index, i)
                            if value and texture then
                                if costString ~= "" then costString = costString .. " " end

                                local canAfford = true
                                -- Check affordability
                                -- GetMerchantItemCostItem doesn't return ID directly, but link does.
                                if link then
                                    local currencyID = string.match(link, "currency:(%d+)")
                                    if currencyID then
                                        local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(currencyID))
                                        if info and info.quantity < value then canAfford = false end
                                    else
                                        -- Item cost
                                        local itemCount = C_Item.GetItemCount(link)
                                        if itemCount < value then canAfford = false end
                                    end
                                end

                                local color = canAfford and "|cffffffff" or "|cffff0000"
                                costString = costString ..
                                    color .. BreakUpLargeNumbers(value) .. " |T" .. texture .. ":12:12:0:0|t|r"
                            end
                        end
                    end
                end

                btn.price:SetText(costString)

                if data.stackCount > 1 then
                    btn.count:SetText(data.stackCount)
                    btn.count:Show()
                else
                    btn.count:Hide()
                end

                if not data.isUsable then
                    btn.icon:SetVertexColor(1.0, 0.1, 0.1)
                else
                    btn.icon:SetVertexColor(1.0, 1.0, 1.0)
                end

                btn:Show()
            else
                btn:Hide()
            end
        else
            btn:Hide()
        end
    end
end

-- Mouse Wheel
frame:SetScript("OnMouseWheel", function(self, delta)
    local min, max = scrollBar:GetMinMaxValues()
    local val = scrollBar:GetValue()
    local step = 1 -- Scroll 1 item for horizontal feel
    -- User asked for horizontal scrolling. Shifting by 1 moves items left.
    if delta > 0 then
        val = val - step
    else
        val = val + step
    end

    if val < min then val = min end
    if val > max then val = max end

    scrollBar:SetValue(val)
end)

-- Header Update
local function UpdateHeader()
    local unit = "npc"
    if not UnitExists(unit) then unit = "target" end

    SetPortraitTexture(frame.portrait, unit)
    frame.merchantName:SetText(UnitName(unit) or "Merchant")

    -- Title/Subtext via C_TooltipInfo
    local titleText = ""
    local data = C_TooltipInfo.GetUnit(unit)
    if data and data.lines then
        -- Default to line 2 if it exists and isn't the name
        if data.lines[2] and data.lines[2].leftText then
            titleText = data.lines[2].leftText
            -- Check if it looks like a level line (e.g. "Level 70")
            if string.find(titleText, "Level") then
                titleText = "" -- UnitLevel is not a title
                -- Try line 3?
                if data.lines[3] and data.lines[3].leftText then
                    titleText = data.lines[3].leftText
                end
            end
        end
    end
    frame.merchantTitle:SetText(titleText)

    -- Check if this is a decor vendor
    isDecorVendor = titleText and (string.find(titleText:lower(), "decor") or string.find(titleText:lower(), "housing"))
end

local isSystemClose = false

-- Events
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("MERCHANT_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        scrollOffset = 0
        scrollBar:SetValue(0)
        UpdateHeader()
        self:Show()
        sfui.merchant.BuildItemList()
        AutoSellGreys()
        AutoRepair()

        -- Delayed refresh for housing decor data (API needs time to load)
        -- Try multiple times with increasing delays to ensure data loads
        C_Timer.After(0.5, function()
            if self:IsShown() then
                sfui.merchant.BuildItemList()
            end
        end)
        C_Timer.After(1.0, function()
            if self:IsShown() then
                sfui.merchant.BuildItemList()
            end
        end)

        -- Ghost Frame: Make default frame invisible and unclickable, but keep it "open"
        if MerchantFrame then
            MerchantFrame:SetAlpha(0)
            MerchantFrame:EnableMouse(false)
            MerchantFrame:SetFrameStrata("BACKGROUND") -- Move to lowest strata
            -- We do NOT call Hide() because that closes the merchant connection
        end
    elseif event == "MERCHANT_CLOSED" then
        isSystemClose = true
        self:Hide()
        isSystemClose = false
    elseif event == "MERCHANT_UPDATE" then
        sfui.merchant.BuildItemList()
    end
end)

-- Allow closing with Escape key
tinsert(UISpecialFrames, "SfuiMerchantFrame")

-- Ensure frame is hidden on load
frame:Hide()
