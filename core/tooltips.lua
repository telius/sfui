local addonName, addon = ...
sfui = sfui or {}
sfui.tooltips = sfui.tooltips or {}

local tooltips = sfui.tooltips
local _G = _G
local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local select = _G.select
local tonumber = _G.tonumber
local table_sort = table.sort
local InCombatLockdown = _G.InCombatLockdown

local issecretvalue = (sfui.safety and sfui.safety.issecretvalue)
    or (sfui.common and sfui.common.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local itemProviders = {}
local spellProviders = {}
local questProviders = {}
local clearCallbacks = {}

local itemSorted = true
local spellSorted = true
local questSorted = true

local _initialized = false
local _itemPassCount = 0
local _spellPassCount = 0
local _questPassCount = 0

local _ctx = {
    tooltip    = nil,
    data       = nil,
    itemID     = nil,
    itemLink   = nil,
    equipLoc   = nil,
    classID    = nil,
    subclassID = nil,
    spellID    = nil,
    questID    = nil,
    inCombat   = false,
}

local function sortByOrder(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.id < b.id
end

local function upsertProvider(list, id, order, fn)
    if type(id) ~= "string" or type(fn) ~= "function" then return end
    local ord = tonumber(order) or 50
    for i = 1, #list do
        if list[i].id == id then
            list[i].order = ord
            list[i].fn = fn
            return
        end
    end
    list[#list + 1] = { id = id, order = ord, fn = fn }
end

function tooltips.RegisterItemProvider(id, order, fn)
    upsertProvider(itemProviders, id, order, fn)
    itemSorted = false
end

function tooltips.RegisterSpellProvider(id, order, fn)
    upsertProvider(spellProviders, id, order, fn)
    spellSorted = false
end

function tooltips.RegisterQuestProvider(id, order, fn)
    upsertProvider(questProviders, id, order, fn)
    questSorted = false
end

function tooltips.RegisterClearCallback(id, fn)
    if type(id) ~= "string" or type(fn) ~= "function" then return end
    clearCallbacks[id] = fn
end

local function isValidPositiveID(val)
    if val == nil or issecretvalue(val) then return false end
    if type(val) ~= "number" then return false end
    return val > 0
end

local function extractItemContext(tooltip, data)
    local itemID, link = nil, nil

    if data and not issecretvalue(data) and type(data) == "table" then
        local rawID = data.id
        if isValidPositiveID(rawID) then
            itemID = rawID
        end
        local rawLink = data.hyperlink
        if rawLink and not issecretvalue(rawLink) and type(rawLink) == "string" then
            link = rawLink
            if not itemID then
                local parsed = tonumber(rawLink:match("item:(%d+)"))
                if isValidPositiveID(parsed) then
                    itemID = parsed
                end
            end
        end
        if (not itemID or not link) and data.guid and not issecretvalue(data.guid) then
            local cItem = _G.C_Item
            local guidLink = cItem and cItem.GetItemLinkByGUID and cItem.GetItemLinkByGUID(data.guid)
            if guidLink and not issecretvalue(guidLink) and type(guidLink) == "string" then
                link = link or guidLink
                if not itemID then
                    local parsed = tonumber(guidLink:match("item:(%d+)"))
                    if isValidPositiveID(parsed) then
                        itemID = parsed
                    end
                end
            end
        end
    end

    local TooltipUtil = _G.TooltipUtil
    if (not itemID or not link) and TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, dispLink, dispID = TooltipUtil.GetDisplayedItem(tooltip)
        if not link and dispLink and not issecretvalue(dispLink) and type(dispLink) == "string" then
            link = dispLink
        end
        if not itemID and isValidPositiveID(dispID) then
            itemID = dispID
        end
    end

    if (not itemID or not link) and tooltip.GetItem then
        local _, tipLink = tooltip:GetItem()
        if tipLink and not issecretvalue(tipLink) and type(tipLink) == "string" then
            link = link or tipLink
            if not itemID then
                local parsed = tonumber(tipLink:match("item:(%d+)"))
                if isValidPositiveID(parsed) then
                    itemID = parsed
                end
            end
        end
    end

    if not isValidPositiveID(itemID) then
        return nil, nil, nil, nil, nil
    end

    local equipLoc, classID, subclassID
    local C_Item = _G.C_Item
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, eqLoc, _, cID, subID = C_Item.GetItemInfoInstant(itemID)
        equipLoc = eqLoc
        classID = cID
        subclassID = subID
    elseif _G.GetItemInfoInstant then
        local _, _, _, eqLoc, _, cID, subID = _G.GetItemInfoInstant(itemID)
        equipLoc = eqLoc
        classID = cID
        subclassID = subID
    end

    return itemID, link, equipLoc, classID, subclassID
end

local function extractSpellID(tooltip, data)
    if data and not issecretvalue(data) and type(data) == "table" then
        local rawID = data.id
        if isValidPositiveID(rawID) then
            return rawID
        end
    end

    local TooltipUtil = _G.TooltipUtil
    if TooltipUtil and TooltipUtil.GetDisplayedSpell then
        local _, id = TooltipUtil.GetDisplayedSpell(tooltip)
        if isValidPositiveID(id) then
            return id
        end
    end

    if tooltip.GetSpell then
        local _, id = tooltip:GetSpell()
        if isValidPositiveID(id) then
            return id
        end
    end

    return nil
end

local function extractQuestID(tooltip, data)
    if tooltip and tooltip._sfuiCurrentType == "quest" and isValidPositiveID(tooltip._sfuiCurrentID) then
        return tooltip._sfuiCurrentID
    end

    if data and not issecretvalue(data) and type(data) == "table" then
        if isValidPositiveID(data.id) then
            return data.id
        end
        local link = data.hyperlink
        if link and not issecretvalue(link) and type(link) == "string" then
            local parsed = tonumber(link:match("quest:(%d+)"))
            if isValidPositiveID(parsed) then
                return parsed
            end
        end
    end

    local savedLink = tooltip and tooltip._sfuiCurrentHyperlink
    if savedLink and not issecretvalue(savedLink) and type(savedLink) == "string" then
        local parsed = tonumber(savedLink:match("quest:(%d+)"))
        if isValidPositiveID(parsed) then
            return parsed
        end
    end

    return nil
end

local function isManagedTooltip(tooltip)
    if not tooltip or issecretvalue(tooltip) or not tooltip.AddLine then
        return false
    end
    if tooltip == sfui.scanTooltip or tooltip._sfuiIsScanner then
        return false
    end
    return true
end

local function dispatchItemTooltip(tooltip, data)
    if not isManagedTooltip(tooltip) then return end
    if #itemProviders == 0 then return end

    local itemID, link, equipLoc, classID, subclassID = extractItemContext(tooltip, data)
    if not itemID then return end

    if tooltip._sfuiItemRendered == itemID then
        return
    end
    tooltip._sfuiItemRendered = itemID

    if not itemSorted then
        table_sort(itemProviders, sortByOrder)
        itemSorted = true
    end

    _itemPassCount = _itemPassCount + 1

    _ctx.tooltip    = tooltip
    _ctx.data       = data
    _ctx.itemID     = itemID
    _ctx.itemLink   = link
    _ctx.equipLoc   = equipLoc
    _ctx.classID    = classID
    _ctx.subclassID = subclassID
    _ctx.spellID    = nil
    _ctx.questID    = nil
    _ctx.inCombat   = (InCombatLockdown and InCombatLockdown()) and true or false

    for i = 1, #itemProviders do
        itemProviders[i].fn(tooltip, _ctx)
    end
end

local function dispatchSpellTooltip(tooltip, data)
    if not isManagedTooltip(tooltip) then return end
    if #spellProviders == 0 then return end

    local spellID = extractSpellID(tooltip, data)
    if not spellID then return end

    if tooltip._sfuiSpellRendered == spellID then
        return
    end
    tooltip._sfuiSpellRendered = spellID

    if not spellSorted then
        table_sort(spellProviders, sortByOrder)
        spellSorted = true
    end

    _spellPassCount = _spellPassCount + 1

    _ctx.tooltip    = tooltip
    _ctx.data       = data
    _ctx.itemID     = nil
    _ctx.itemLink   = nil
    _ctx.equipLoc   = nil
    _ctx.classID    = nil
    _ctx.subclassID = nil
    _ctx.spellID    = spellID
    _ctx.questID    = nil
    _ctx.inCombat   = (InCombatLockdown and InCombatLockdown()) and true or false

    for i = 1, #spellProviders do
        spellProviders[i].fn(tooltip, _ctx)
    end
end

local function dispatchQuestTooltip(tooltip, data)
    if not isManagedTooltip(tooltip) then return end
    if #questProviders == 0 then return end

    local questID = extractQuestID(tooltip, data)
    if not questID then return end

    if tooltip._sfuiQuestRendered == questID then
        return
    end
    tooltip._sfuiQuestRendered = questID

    if not questSorted then
        table_sort(questProviders, sortByOrder)
        questSorted = true
    end

    _questPassCount = _questPassCount + 1

    _ctx.tooltip    = tooltip
    _ctx.data       = data
    _ctx.itemID     = nil
    _ctx.itemLink   = (data and not issecretvalue(data) and type(data) == "table" and not issecretvalue(data.hyperlink) and data.hyperlink) or nil
    _ctx.equipLoc   = nil
    _ctx.classID    = nil
    _ctx.subclassID = nil
    _ctx.spellID    = nil
    _ctx.questID    = questID
    _ctx.inCombat   = (InCombatLockdown and InCombatLockdown()) and true or false

    for i = 1, #questProviders do
        questProviders[i].fn(tooltip, _ctx)
    end
end

local function dispatchMacroTooltip(tooltip, data)
    if not isManagedTooltip(tooltip) then return end
    local spellID = extractSpellID(tooltip, data)
    if spellID then
        dispatchSpellTooltip(tooltip, data)
        return
    end
    dispatchItemTooltip(tooltip, data)
end

local function onTooltipCleared(tooltip)
    if not tooltip or issecretvalue(tooltip) then return end
    tooltip._sfuiItemRendered = nil
    tooltip._sfuiSpellRendered = nil
    tooltip._sfuiQuestRendered = nil
    for _, fn in pairs(clearCallbacks) do
        fn(tooltip)
    end
end

tooltips.ClearStamp = onTooltipCleared

local hookedClearTips = {}
local function hookTooltipClear(tip)
    if not tip or hookedClearTips[tip] then return end
    hookedClearTips[tip] = true
    if tip.HookScript then
        tip:HookScript("OnTooltipCleared", onTooltipCleared)
        tip:HookScript("OnHide", onTooltipCleared)
    end
    if _G.hooksecurefunc and tip.ClearLines then
        _G.hooksecurefunc(tip, "ClearLines", onTooltipCleared)
    end
end

function tooltips.HookTooltip(tip)
    if not tip then return end
    hookTooltipClear(tip)
    local dataProcessor = _G.TooltipDataProcessor
    local enumType = _G.Enum and _G.Enum.TooltipDataType
    if not (dataProcessor and dataProcessor.AddTooltipPostCall and enumType) then
        if not tip._sfuiLegacyPipelineHooked and tip.HookScript then
            tip._sfuiLegacyPipelineHooked = true
            tip:HookScript("OnTooltipSetItem", dispatchItemTooltip)
            tip:HookScript("OnTooltipSetSpell", dispatchSpellTooltip)
        end
    end
end

local _dialogueUITooltipHooked = false
local _duiDataProxy = { id = nil, hyperlink = nil }

local function hookDialogueUITooltip()
    if _dialogueUITooltipHooked then return end
    local duiAPI = _G.DialogueUIAPI
    if not (duiAPI and type(duiAPI.AddItemTooltipProcessorExternal) == "function") then return end
    _dialogueUITooltipHooked = true

    duiAPI.AddItemTooltipProcessorExternal(function(tooltip, itemID, itemLink)
        if not tooltip or issecretvalue(tooltip) then return false end
        hookTooltipClear(tooltip)
        onTooltipCleared(tooltip)
        local beforeLines = (tooltip.NumLines and tooltip:NumLines()) or 0
        _duiDataProxy.id = itemID
        _duiDataProxy.hyperlink = itemLink
        dispatchItemTooltip(tooltip, _duiDataProxy)
        local afterLines = (tooltip.NumLines and tooltip:NumLines()) or 0
        return afterLines > beforeLines
    end)
end

function tooltips.Init()
    hookDialogueUITooltip()
    if _initialized then
        local sfuiTip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip
        if sfuiTip then
            tooltips.HookTooltip(sfuiTip)
        end
        return
    end
    _initialized = true

    local dataProcessor = _G.TooltipDataProcessor
    local enumType = _G.Enum and _G.Enum.TooltipDataType

    if dataProcessor and dataProcessor.AddTooltipPostCall and enumType then
        if enumType.Item then
            dataProcessor.AddTooltipPostCall(enumType.Item, dispatchItemTooltip)
        end
        if enumType.Toy then
            dataProcessor.AddTooltipPostCall(enumType.Toy, dispatchItemTooltip)
        end
        if enumType.Spell then
            dataProcessor.AddTooltipPostCall(enumType.Spell, dispatchSpellTooltip)
        end
        if enumType.UnitAura then
            dataProcessor.AddTooltipPostCall(enumType.UnitAura, dispatchSpellTooltip)
        end
        if enumType.Macro then
            dataProcessor.AddTooltipPostCall(enumType.Macro, dispatchMacroTooltip)
        end
        if enumType.Quest then
            dataProcessor.AddTooltipPostCall(enumType.Quest, dispatchQuestTooltip)
        end
    end

    local sfuiTip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip
    local targets = {
        _G.GameTooltip,
        _G.ItemRefTooltip,
        sfuiTip,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
    }
    for i = 1, #targets do
        local t = targets[i]
        if t then
            tooltips.HookTooltip(t)
        end
    end
end

local _debugInfo = {}
function tooltips.GetDebugInfo()
    _debugInfo.initialized    = _initialized
    _debugInfo.itemProviders  = #itemProviders
    _debugInfo.spellProviders = #spellProviders
    _debugInfo.questProviders = #questProviders
    _debugInfo.itemPasses     = _itemPassCount
    _debugInfo.spellPasses    = _spellPassCount
    _debugInfo.questPasses    = _questPassCount
    return _debugInfo
end

tooltips.OnInit = tooltips.Init
tooltips.OnEnable = tooltips.Init

if sfui.RegisterModule then
    sfui.RegisterModule("tooltips", tooltips)
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", tooltips.Init)
    sfui.events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if loadedAddon == "DialogueUI" then
            hookDialogueUITooltip()
        end
    end)
end

tooltips.Init()
