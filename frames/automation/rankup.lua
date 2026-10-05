local addonName, addon = ...
sfui = sfui or {}
sfui.rankup = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/automation/rankup.lua
--  Automatic Spell Rank Upgrade on Action Bars (Classic Forever / Camelot)
--
--  Automatically replaces lower-rank spells on action bars (slots 1-120) with
--  the newly learned highest rank when training at a class trainer.
--  Preserves intentional downranking (e.g. Frostbolt Rank 1 alongside max rank).
-- ══════════════════════════════════════════════════════════════════════════════

-- Rank-up automation is exclusive to Classic Forever (Camelot) & Classic Era where spell ranks exist.
if not (sfui.isCamelot or sfui.isClassic or sfui.isForever) then return end

local _G = _G
local InCombatLockdown = _G.InCombatLockdown
local ClearCursor = _G.ClearCursor
local PlaceAction = _G.PlaceAction
local GetActionInfo = _G.GetActionInfo
local GetCursorInfo = _G.GetCursorInfo
local C_Spell = _G.C_Spell
local C_SpellBook = _G.C_SpellBook
local C_Timer = _G.C_Timer
local tonumber = _G.tonumber
local string_lower = _G.string.lower
local string_format = _G.string.format
local string_match = _G.string.match
local table_insert = _G.table.insert
local ipairs, pairs = _G.ipairs, _G.pairs

local scanTimer = nil
local retryTimer = nil

local function parseRank(subtext)
    if not subtext or subtext == "" then return 0 end
    local r = string_match(subtext, "(%d+)")
    return tonumber(r) or 0
end

local function getSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        if name and name ~= "" then return name end
    end
    return nil
end

local function getSpellSubtext(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellSubtext then
        local sub = C_Spell.GetSpellSubtext(spellID)
        if sub and sub ~= "" then return sub end
    end
    if _G.GetSpellSubtext then
        local sub = _G.GetSpellSubtext(spellID)
        if sub and sub ~= "" then return sub end
    end
    return nil
end

local function pickupSpell(spellID, slotIndex, spellBank)
    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(spellID)
    elseif _G.PickupSpell then
        _G.PickupSpell(spellID)
    elseif slotIndex and C_SpellBook and C_SpellBook.PickupSpellBookItem then
        C_SpellBook.PickupSpellBookItem(slotIndex, spellBank or (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 1)
    elseif slotIndex and _G.PickupSpellBookItem then
        _G.PickupSpellBookItem(slotIndex, _G.BOOKTYPE_SPELL or "spell")
    end
end

local function GetHighestKnownSpells()
    local knownHighest = {}
    local spellBank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 1

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
        for skillLineIndex = 1, numSkillLines do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
            if skillLineInfo and not skillLineInfo.shouldHide and not skillLineInfo.offSpecID then
                local offset = skillLineInfo.itemIndexOffset or 0
                local numSpells = skillLineInfo.numSpellBookItems or 0
                for i = 1, numSpells do
                    local slotIndex = offset + i
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
                    if itemInfo and not itemInfo.isPassive and not itemInfo.isOffSpec then
                        local spellID = itemInfo.spellID or itemInfo.actionID
                        local spellName = itemInfo.name or (spellID and getSpellName(spellID))
                        local subtext = itemInfo.subName or (spellID and getSpellSubtext(spellID))
                        local rank = parseRank(subtext)
                        if spellID and spellName and rank > 0 then
                            local nameKey = string_lower(spellName)
                            if not knownHighest[nameKey] or rank > knownHighest[nameKey].rank then
                                knownHighest[nameKey] = {
                                    spellID   = spellID,
                                    rank      = rank,
                                    name      = spellName,
                                    subtext   = subtext,
                                    slotIndex = slotIndex,
                                    spellBank = spellBank,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fallback to classic GetNumSpellTabs if C_SpellBook didn't populate anything
    if not next(knownHighest) and _G.GetNumSpellTabs then
        local numTabs = _G.GetNumSpellTabs()
        for tab = 1, numTabs do
            local _, _, offset, numSpells = _G.GetSpellTabInfo(tab)
            for s = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
                local spellName, subName = _G.GetSpellBookItemName(s, _G.BOOKTYPE_SPELL or "spell")
                local slotType, spellID = _G.GetSpellBookItemInfo(s, _G.BOOKTYPE_SPELL or "spell")
                if slotType == "SPELL" and spellName then
                    local rank = parseRank(subName)
                    if spellID and rank > 0 then
                        local nameKey = string_lower(spellName)
                        if not knownHighest[nameKey] or rank > knownHighest[nameKey].rank then
                            knownHighest[nameKey] = {
                                spellID   = spellID,
                                rank      = rank,
                                name      = spellName,
                                subtext   = subName,
                                slotIndex = s,
                                spellBank = _G.BOOKTYPE_SPELL or "spell",
                            }
                        end
                    end
                end
            end
        end
    end

    return knownHighest
end

local function GetBarSpells()
    local barSpells = {}

    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and id > 0 then
            local spellName = getSpellName(id)
            if spellName then
                local subtext = getSpellSubtext(id)
                local rank = parseRank(subtext)
                if rank > 0 then
                    local nameKey = string_lower(spellName)
                    if not barSpells[nameKey] then
                        barSpells[nameKey] = { maxRank = 0, slots = {} }
                    end
                    table_insert(barSpells[nameKey].slots, {
                        slot    = slot,
                        spellID = id,
                        rank    = rank,
                    })
                    if rank > barSpells[nameKey].maxRank then
                        barSpells[nameKey].maxRank = rank
                    end
                end
            end
        end
    end

    return barSpells
end

function sfui.rankup.ScanAndUpgrade()
    if SfuiDB and SfuiDB.autoRankUp == false then return end
    if InCombatLockdown and InCombatLockdown() then
        return
    end

    -- Never interfere if the player is currently dragging an item/spell on cursor
    if GetCursorInfo and GetCursorInfo() then
        if not retryTimer then
            retryTimer = C_Timer.NewTimer(0.5, function()
                retryTimer = nil
                sfui.rankup.ScanAndUpgrade()
            end)
        end
        return
    end

    local knownHighest = GetHighestKnownSpells()
    if not next(knownHighest) then return end

    local barSpells = GetBarSpells()

    local upgrades = {}
    for nameKey, barData in pairs(barSpells) do
        local highest = knownHighest[nameKey]
        if highest and highest.rank > barData.maxRank then
            -- Replace any slot holding the previous maximum rank on the bars
            for _, entry in ipairs(barData.slots) do
                if entry.rank == barData.maxRank and entry.spellID ~= highest.spellID then
                    table_insert(upgrades, {
                        slot       = entry.slot,
                        oldSpellID = entry.spellID,
                        newSpellID = highest.spellID,
                        name       = highest.name,
                        oldRank    = entry.rank,
                        newRank    = highest.rank,
                        slotIndex  = highest.slotIndex,
                        spellBank  = highest.spellBank,
                    })
                end
            end
        end
    end

    if #upgrades == 0 then return end

    for _, up in ipairs(upgrades) do
        if not (InCombatLockdown and InCombatLockdown()) then
            ClearCursor()
            pickupSpell(up.newSpellID, up.slotIndex, up.spellBank)
            local cursorType = GetCursorInfo()
            if cursorType == "spell" then
                PlaceAction(up.slot)
                ClearCursor()

                local cyan = (sfui.config and sfui.config.colors and sfui.config.colors.cyan) or { 0.2, 0.9, 1.0 }
                local cc = string_format("|cff%02x%02x%02x", cyan[1] * 255, cyan[2] * 255, cyan[3] * 255)
                sfui.common.print(string_format("auto rank-up: %s%s|r (rank %d -> rank %d) on action slot %d",
                    cc, up.name, up.oldRank, up.newRank, up.slot))
            else
                ClearCursor()
            end
        else
            break
        end
    end
end

local function RequestScan()
    if SfuiDB and SfuiDB.autoRankUp == false then return end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if scanTimer then
        scanTimer:Cancel()
        scanTimer = nil
    end
    scanTimer = C_Timer.NewTimer(0.25, function()
        scanTimer = nil
        sfui.rankup.ScanAndUpgrade()
    end)
end

sfui.events.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", function()
    RequestScan()
end)

sfui.events.RegisterEvent("LEARNED_SPELL_IN_TAB", function()
    RequestScan()
end)

sfui.events.RegisterEvent("TRAINER_UPDATE", function()
    RequestScan()
end)

sfui.events.RegisterEvent("TRAINER_CLOSED", function()
    RequestScan()
end)

sfui.events.RegisterEvent("SPELLS_CHANGED", function()
    RequestScan()
end)

sfui.events.RegisterEvent("PLAYER_LEVEL_UP", function()
    RequestScan()
end)

sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(1.2, RequestScan)
end)

sfui.rankup.OnInit = function()
    if SfuiDB and SfuiDB.autoRankUp == nil then
        SfuiDB.autoRankUp = true
    end
end

sfui.rankup.OnEnable = sfui.rankup.OnInit
sfui.RegisterModule("rankup", sfui.rankup)
