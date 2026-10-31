local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}
sfui.sync.trade = sfui.sync.trade or {}

local sync     = sfui.sync
local multibox = sfui.sync.multibox
local trade    = sfui.sync.trade
local common   = sfui.common

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/trade.lua
--  Synced-Party Trade Auto-Routing (Extending `sfui.alts.mail` + Professions)
--
--  Loaded and active ONLY when in a party with a synced character:
--    1. Extends `sfui.alts.mail` (`frames/alts/mail_data.lua`) item assignments,
--       tradeskill categories, recipe-usage fallback, and disenchanter BoE rules
--       into face-to-face trading (`TRADE_SHOW`).
--    2. Falls back to synced profession data (`SfuiDB.alts[guid].professions`)
--       when a category is not explicitly assigned in `altMailRouting`.
--    3. Provides `give mats` and `dump junk` buttons on `TradeFrame` when trading
--       with a synced character.
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local select = _G.select
local string_lower = string.lower
local string_format = string.format
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat
local C_Container = _G.C_Container
local C_Timer = _G.C_Timer
local UnitGUID = _G.UnitGUID
local IsShiftKeyDown = _G.IsShiftKeyDown
local ClearCursor = _G.ClearCursor
local CursorHasItem = _G.CursorHasItem
local ClickTradeButton = _G.ClickTradeButton
local GetTradePlayerItemInfo = _G.GetTradePlayerItemInfo

local TRADE_SLOTS     = (_G.MAX_TRADE_ITEMS and (_G.MAX_TRADE_ITEMS - 1)) or 6
local isActive        = false
local currentPartner  = nil
local currentAltGUID  = nil
local giveMatsBtn     = nil
local dumpJunkBtn     = nil

local REASON_LABELS = {
    assigned_item              = "assigned item",
    disenchant_boe             = "disenchant boe",
    category_sendHerbs         = "herbs",
    category_sendOre           = "ore & stone",
    category_sendCloth         = "cloth",
    category_sendLeather       = "leather",
    category_sendEnchanting    = "enchanting",
    category_sendGems          = "gems",
    category_sendElemental     = "elemental",
    category_sendCooking       = "cooking",
    category_sendEngineering   = "engineering",
    category_sendInscription   = "inscription",
    category_sendComprehension = "comprehension",
}

local function resolve_partner_alt(partnerGUID, partnerName)
    if not SfuiDB or type(SfuiDB.alts) ~= "table" then return nil end
    if partnerGUID and SfuiDB.alts[partnerGUID] then
        return partnerGUID
    end
    if partnerName and partnerName ~= "" then
        for guid, alt in pairs(SfuiDB.alts) do
            if type(alt) == "table" and multibox.SameChar(alt.name, partnerName) then
                return guid
            end
        end
    end
    return nil
end

local function build_prof_map(guid)
    local map = {}
    local mail = sfui.alts and sfui.alts.mail
    if not mail or not mail.GetAltProfessions or not guid then return map end
    for _, p in ipairs(mail.GetAltProfessions(guid) or {}) do
        if p.baseKey then
            map[p.baseKey] = tonumber(p.rank) or 1
        end
    end
    return map
end

local function match_profession_fallback(itemID, itemLink, partnerProfs, myProfs, manual)
    if not next(partnerProfs) then return nil end
    local GetItemInfo = (common and common.get_item_info) or _G.GetItemInfo
    local GetItemInfoInstant = (common and common.get_item_instant_info) or _G.GetItemInfoInstant
    local itemName, _, quality, _, _, _, _, _, _, _, _, classID, subclassID, bindType = GetItemInfo(itemLink or itemID)
    if (not classID or not subclassID) and GetItemInfoInstant and itemID then
        local _, _, _, _, _, cID, scID = GetItemInfoInstant(itemID)
        classID = classID or cID
        subclassID = subclassID or scID
    end
    if not classID then return nil end

    local tradeClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Tradegoods) or 7
    local gemClass    = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Gem) or 3
    local weaponClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Weapon) or 2
    local armorClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Armor) or 4

    local prof1, prof2, label = nil, nil, nil

    if classID == tradeClass or classID == 7 then
        if subclassID == 5 then
            prof1, label = "tailoring", "cloth"
        elseif subclassID == 6 then
            prof1, label = "leatherworking", "leather"
        elseif subclassID == 9 then
            prof1, prof2, label = "alchemy", "inscription", "herbs"
        elseif subclassID == 7 then
            local lowerName = string_lower(itemName or "")
            if lowerName:find("ore") then
                prof1, label = "mining", "ore"
            else
                prof1, prof2, label = "blacksmithing", "engineering", "bars & stone"
            end
        elseif subclassID == 12 then
            prof1, label = "enchanting", "enchanting"
        elseif subclassID == 0 or subclassID == 1 or subclassID == 2 or subclassID == 17 then
            prof1, label = "engineering", "engineering"
        elseif subclassID == 16 then
            prof1, label = "inscription", "inscription"
        elseif subclassID == 4 or subclassID == 3 then
            prof1, label = "jewelcrafting", "gems"
        end
    elseif classID == gemClass or classID == 3 then
        prof1, label = "jewelcrafting", "gems"
    elseif bindType == 2 and quality == 2 and (classID == weaponClass or classID == armorClass or classID == 2 or classID == 4) then
        prof1, label = "enchanting", "disenchant boe"
    end

    if not prof1 then return nil end

    local partnerHas = (partnerProfs[prof1] ~= nil) or (prof2 ~= nil and partnerProfs[prof2] ~= nil)
    if not partnerHas then return nil end

    local myHas = (myProfs[prof1] ~= nil) or (prof2 ~= nil and myProfs[prof2] ~= nil)
    if myHas and not manual then
        return nil, true -- Kept because we also use this profession
    end
    return label, false
end

local function scan_routed_items_for_partner(partnerAltGUID, partnerName, manual)
    local list = {}
    local keptSharedCount = 0
    if not C_Container then return list, 0 end

    local mail = sfui.alts and sfui.alts.mail
    local lastBag = (mail and mail.GetLastBagIndex and mail.GetLastBagIndex()) or 4
    local myGUID = UnitGUID and UnitGUID("player")
    local partnerProfs = build_prof_map(partnerAltGUID)
    local myProfs = build_prof_map(myGUID)
    local candidateAlts = (mail and mail.GetAlts and mail.GetAlts(false)) or nil

    for bag = 0, lastBag do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and info.hyperlink and not info.isLocked and not info.isBound then
                if not (mail and mail.IsItemIgnored and mail.IsItemIgnored(info.itemID)) then
                    local matchedLabel = nil
                    local routedElsewhere = false

                    -- 1. Check sfui.alts.mail routing rules first (pass pre-built candidateAlts & info)
                    if mail and mail.FindDestinationForBagItem then
                        local destGUID, destName, _, reason = mail.FindDestinationForBagItem(bag, slot, candidateAlts, info, true)
                        if destGUID or destName then
                            if (partnerAltGUID and destGUID == partnerAltGUID)
                                or (partnerName and destName and multibox.SameChar(destName, partnerName)) then
                                matchedLabel = REASON_LABELS[reason] or "routed"
                            else
                                routedElsewhere = true
                            end
                        end
                    end

                    -- 2. Fallback to synced profession matching if not routed to another alt
                    if not matchedLabel and not routedElsewhere then
                        local profLabel, keptShared = match_profession_fallback(info.itemID, info.hyperlink, partnerProfs, myProfs, manual)
                        if profLabel then
                            matchedLabel = profLabel
                        elseif keptShared then
                            keptSharedCount = keptSharedCount + 1
                        end
                    end

                    if matchedLabel then
                        table_insert(list, {
                            bag   = bag,
                            slot  = slot,
                            count = info.stackCount or 1,
                            label = matchedLabel,
                            link  = info.hyperlink,
                        })
                    end
                end
            end
        end
    end

    table_sort(list, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        if a.bag ~= b.bag then
            return a.bag < b.bag
        end
        return a.slot < b.slot
    end)

    return list, keptSharedCount
end

local function put_stacks_in_trade(stacks)
    local placed = {}
    local tslot = 1
    for _, item in ipairs(stacks) do
        while tslot <= TRADE_SLOTS and (GetTradePlayerItemInfo and GetTradePlayerItemInfo(tslot)) do
            tslot = tslot + 1
        end
        if tslot > TRADE_SLOTS then break end
        if ClearCursor then ClearCursor() end
        if C_Container and C_Container.PickupContainerItem then
            C_Container.PickupContainerItem(item.bag, item.slot)
        end
        if CursorHasItem and CursorHasItem() and ClickTradeButton then
            ClickTradeButton(tslot)
            if ClearCursor then ClearCursor() end
            placed[#placed + 1] = item
            tslot = tslot + 1
        else
            if ClearCursor then ClearCursor() end
        end
    end
    return placed
end

function trade.FillRoutedTrade(manual)
    if not _G.TradeFrame or not _G.TradeFrame:IsShown() or not currentPartner then return end
    local stacks, keptShared = scan_routed_items_for_partner(currentAltGUID, currentPartner, manual == true)

    if #stacks == 0 then
        if manual and common and common.print then
            common.print(string_format("sync: no routed or profession items found for |cff00ffff%s|r.",
                string_lower(multibox.CommandName(currentPartner))))
        elseif keptShared > 0 and common and common.print then
            common.print(string_format("sync: kept %d shared profession stack(s) — click |cff00ffffgive mats|r on the trade frame to hand them over.",
                keptShared))
        end
        return
    end

    local placed = put_stacks_in_trade(stacks)
    if #placed > 0 and common and common.print then
        local seenLabels = {}
        local labels = {}
        for _, p in ipairs(placed) do
            if p.label and not seenLabels[p.label] then
                seenLabels[p.label] = true
                labels[#labels + 1] = p.label
            end
        end
        local remaining = #stacks - #placed
        local remStr = remaining > 0 and string_format(" (%d more waiting — trade again)", remaining) or ""
        common.print(string_format("sync: placed %d stack(s) for |cff00ffff%s|r [%s]%s.",
            #placed, string_lower(multibox.CommandName(currentPartner)), table_concat(labels, ", "), remStr))
    end
end

function trade.FillVendorJunkTrade()
    if not _G.TradeFrame or not _G.TradeFrame:IsShown() or not currentPartner then return end
    if not C_Container then return end

    local mail = sfui.alts and sfui.alts.mail
    local lastBag = (mail and mail.GetLastBagIndex and mail.GetLastBagIndex()) or 4
    local GetItemInfo = (common and common.get_item_info) or _G.GetItemInfo
    local stacks = {}

    for bag = 0, lastBag do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and info.hyperlink and not info.isLocked and not info.isBound and not info.hasNoValue then
                if not (mail and mail.IsItemIgnored and mail.IsItemIgnored(info.itemID)) then
                    local quality = info.quality
                    local sellPrice = select(11, GetItemInfo(info.hyperlink))
                    if quality == 0 and (tonumber(sellPrice) or 0) > 0 then
                        table_insert(stacks, {
                            bag   = bag,
                            slot  = slot,
                            count = info.stackCount or 1,
                            value = (tonumber(sellPrice) or 0) * (info.stackCount or 1),
                        })
                    end
                end
            end
        end
    end

    table_sort(stacks, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.value > b.value
    end)

    if #stacks == 0 then
        if common and common.print then
            common.print("sync: no tradable grey/junk vendor items in bags.")
        end
        return
    end

    local placed = put_stacks_in_trade(stacks)
    local remaining = #stacks - #placed
    if #placed > 0 and common and common.print then
        local remStr = remaining > 0 and string_format(" (%d more waiting)", remaining) or ""
        common.print(string_format("sync: placed %d vendor junk stack(s) for |cff00ffff%s|r%s.",
            #placed, string_lower(multibox.CommandName(currentPartner)), remStr))
    end
end

local function ensure_trade_buttons()
    if giveMatsBtn or not _G.TradeFrame or not common or not common.create_flat_button then return end

    giveMatsBtn = common.create_flat_button(_G.TradeFrame, "give mats", 76, 20, function()
        trade.FillRoutedTrade(true)
    end)
    giveMatsBtn:SetPoint("BOTTOMRIGHT", _G.TradeFrame, "TOPRIGHT", 0, 2)
    giveMatsBtn.tooltip = "places items routed to this character (from alt mail routing & professions) into the trade window, including shared profession mats."

    dumpJunkBtn = common.create_flat_button(_G.TradeFrame, "dump junk", 76, 20, function()
        trade.FillVendorJunkTrade()
    end)
    dumpJunkBtn:SetPoint("RIGHT", giveMatsBtn, "LEFT", -4, 0)
    dumpJunkBtn.tooltip = "places tradable grey/junk vendor items into the trade window so one character with bag space can sell them."
end

local function set_buttons_shown(shown)
    if giveMatsBtn then giveMatsBtn:SetShown(shown) end
    if dumpJunkBtn then dumpJunkBtn:SetShown(shown) end
end

local function on_trade_show()
    if not isActive then return end
    local partnerName = multibox.FullName("NPC")
    local partnerGUID = UnitGUID and UnitGUID("NPC")

    if not partnerName or not (multibox.IsSyncedCharacter(partnerGUID) or multibox.IsSyncedCharacter(partnerName)) then
        currentPartner = nil
        currentAltGUID = nil
        set_buttons_shown(false)
        return
    end

    currentPartner = partnerName
    currentAltGUID = resolve_partner_alt(partnerGUID, partnerName)
    ensure_trade_buttons()
    set_buttons_shown(true)

    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoTrade == false then return end
    if sync.IsAway and sync.IsAway() then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end

    local expectedPartner = currentPartner
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            if isActive and currentPartner == expectedPartner and _G.TradeFrame and _G.TradeFrame:IsShown() then
                trade.FillRoutedTrade(false)
            end
        end)
    end
end

local function on_trade_closed()
    currentPartner = nil
    currentAltGUID = nil
    set_buttons_shown(false)
end

function trade.Enable()
    if isActive then return end
    isActive = true
    if sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("TRADE_SHOW", on_trade_show)
        sfui.events.RegisterEvent("TRADE_CLOSED", on_trade_closed)
    end
end

function trade.Disable()
    if not isActive then return end
    isActive = false
    currentPartner = nil
    currentAltGUID = nil
    set_buttons_shown(false)
    if sfui.events and sfui.events.UnregisterEvent then
        sfui.events.UnregisterEvent("TRADE_SHOW", on_trade_show)
        sfui.events.UnregisterEvent("TRADE_CLOSED", on_trade_closed)
    end
end

if multibox and multibox.RegisterPartySubmodule then
    multibox.RegisterPartySubmodule(trade)
end

