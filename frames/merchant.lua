-- frames/merchant.lua
-- Custom 4x7 grid merchant frame for sfui

sfui = sfui or {}
sfui.merchant = {}

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

-- Close Button
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- Scroll Variables
local scrollOffset = 0
local totalMerchantItems = 0

-- Item Buttons Array
local buttons = {}

local function CreateItemButton(id)
    local btn = CreateFrame("Button", "SfuiMerchantItem" .. id, frame, "BackdropTemplate")
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
    btn.nameStub:SetPoint("TOPLEFT", iconWrap, "TOPRIGHT", 5, 0)
    btn.nameStub:SetJustifyH("LEFT")

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
            if button == "RightButton" then
                BuyMerchantItem(self:GetID())
            else
                PickupMerchantItem(self:GetID())
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
    local btn = CreateItemButton(i)
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



local currencyDisplays = {}

local function UpdateCurrencies()
    -- Hide old
    for _, f in pairs(currencyDisplays) do f:Hide() end

    local currencies = {}
    local numItems = GetMerchantNumItems() -- Global check, assumed valid now

    for i = 1, numItems do
        local itemInfo = C_MerchantFrame.GetItemInfo(i)
        if itemInfo then
            -- Check simple currencyID first (API 12.0)
            if itemInfo.currencyID then
                local info = C_CurrencyInfo.GetCurrencyInfo(itemInfo.currencyID)
                if info then
                    if not currencies[info.name] then
                        currencies[info.name] = { texture = info.iconFileID, count = info.quantity }
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
                            if not currencies[currencyName] then
                                local count = 0
                                local currencyID = link and string.match(link, "currency:(%d+)")
                                if currencyID then
                                    local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(currencyID))
                                    if info then count = info.quantity end
                                else
                                    count = C_Item.GetItemCount(link)
                                end
                                currencies[currencyName] = { texture = texture, count = count }
                            end
                        end
                    end
                end
            end
        end
    end

    local idx = 0
    for name, data in pairs(currencies) do
        idx = idx + 1
        local display = currencyDisplays[idx]
        if not display then
            display = CreateFrame("Frame", nil, currencyFrame)
            display:SetSize(100, 20)

            display.icon = display:CreateTexture(nil, "ARTWORK")
            display.icon:SetSize(16, 16)
            display.icon:SetPoint("LEFT")

            display.text = display:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            display.text:SetPoint("LEFT", display.icon, "RIGHT", 5, 0)

            currencyDisplays[idx] = display
        end

        display.icon:SetTexture(data.texture)
        display.text:SetText(BreakUpLargeNumbers(data.count))

        -- Logic to stack from right to left
        display:ClearAllPoints()
        if idx == 1 then
            display:SetPoint("RIGHT", 0, 0)
        else
            local prev = currencyDisplays[idx - 1]
            display:SetPoint("RIGHT", prev, "LEFT", -15, 0) -- 15px gap
        end

        -- Resize frame to fit content to allow proper stacking if needed,
        -- but 'display' is just a container.
        -- Better: calculate width dynamically
        local textWidth = display.text:GetStringWidth()
        display:SetWidth(16 + 5 + textWidth + 2)

        display:Show()
    end
end


sfui.merchant.UpdateMerchant = function()
    local numItems = GetMerchantNumItems()
    totalMerchantItems = numItems

    -- Setup ScrollBar
    local maxOffset = math.max(0, math.ceil((numItems - ITEMS_PER_PAGE) / NUM_COLS) * NUM_COLS)
    -- actually we scroll by row.
    -- total rows = ceil(numItems / cols)
    -- visible rows = num_rows
    -- max scroll = (total_rows - visible_rows) * cols ?
    -- Let's make step 4 (NUM_COLS).

    local totalRows = math.ceil(numItems / NUM_COLS)
    local maxRowScroll = math.max(0, totalRows - NUM_ROWS)
    scrollBar:SetMinMaxValues(0, maxRowScroll * NUM_COLS)
    scrollBar:SetValueStep(NUM_COLS)
    -- thumb size ratio?

    -- If we moved past max, clamp
    -- scrollOffset should align to row

    local itemInfo
    for i = 1, ITEMS_PER_PAGE do
        local btn = buttons[i]
        local index = scrollOffset + i

        if index <= numItems then
            itemInfo = C_MerchantFrame.GetItemInfo(index)

            if itemInfo and itemInfo.name then
                btn:SetID(index)
                btn.hasItem = true
                btn.icon:SetTexture(itemInfo.texture)

                -- Rarity Color
                if itemInfo.quality then
                    local r, g, b = C_Item.GetItemQualityColor(itemInfo.quality)
                    btn.nameStub:SetTextColor(r, g, b, 1)
                else
                    btn.nameStub:SetTextColor(1, 1, 1, 1)
                end

                -- Truncation Logic
                local maxWidth = 135 -- approx width available
                local text = itemInfo.name
                btn.nameStub:SetText(text)
                if btn.nameStub:GetStringWidth() > maxWidth then
                    -- Strategy: Truncate 1st word first letter.
                    -- If still too long, truncate 2nd word.
                    local words = {}
                    for w in string.gmatch(text, "%S+") do table.insert(words, w) end

                    if #words >= 1 then
                        -- Truncate 1st word
                        local w1 = words[1]
                        words[1] = string.sub(w1, 1, 1) .. "."

                        text = table.concat(words, " ")
                        btn.nameStub:SetText(text)

                        if btn.nameStub:GetStringWidth() > maxWidth and #words >= 2 then
                            -- Truncate 2nd word
                            local w2 = words[2]
                            words[2] = string.sub(w2, 1, 1) .. "."
                            text = table.concat(words, " ")
                            btn.nameStub:SetText(text)
                        end
                    end
                end

                -- btn.nameStub:SetText(itemInfo.name) -- Replaced by logic above

                -- Extended Cost Logic
                if itemInfo.hasExtendedCost then
                    btn.price:SetText("Currency")
                    -- Ideally show specific cost if possible, but space is limited
                else
                    btn.price:SetText(C_CurrencyInfo.GetCoinTextureString(itemInfo.price))
                end

                if itemInfo.stackCount > 1 then
                    btn.count:SetText(itemInfo.stackCount)
                    btn.count:Show()
                else
                    btn.count:Hide()
                end

                if not itemInfo.isUsable then
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
    if delta > 0 then
        val = val - NUM_COLS
    else
        val = val + NUM_COLS
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
end

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
        sfui.merchant.UpdateMerchant()
        if MerchantFrame then MerchantFrame:Hide() end
    elseif event == "MERCHANT_CLOSED" then
        self:Hide()
    elseif event == "MERCHANT_UPDATE" then
        sfui.merchant.UpdateMerchant()
    end
end)
