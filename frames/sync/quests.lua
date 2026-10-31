local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}
sfui.sync.quests = sfui.sync.quests or {}

local sync     = sfui.sync
local multibox = sfui.sync.multibox
local quests   = sfui.sync.quests

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/quests.lua
--  Synced-Party Quest, Gossip, Dialog, Abandon & Smart Reward Selection
--
--  Loaded and active ONLY when in a party with a synced character:
--    1. Synchronized Quest Abandon (`DELTA_QUEST_ABANDON`) with completed-quest
--       safety protection.
--    2. Multi-Step Turn-In Catch-Up (`GossipFrame` -> `QuestFrameProgressPanel`
--       -> `QuestFrameRewardPanel`).
--    3. Smart Quest Reward Selection & Manual Override (`QuestInfoFrame.itemChoice`,
--       armor/class fit, and highest vendor value fallback).
--    4. Gossip / Dialog / Safe StaticPopup Mirroring & Missing-Quest Auto-Share.
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local select = _G.select
local string_lower = string.lower
local string_match = string.match
local string_format = string.format
local table_remove = table.remove
local wipe = _G.wipe
local GetTime = _G.GetTime
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitLevel = _G.UnitLevel
local IsShiftKeyDown = _G.IsShiftKeyDown
local C_Timer = _G.C_Timer

local PENDING_SECONDS      = 8.0
local pendingDialogChoices = {}
local gossipCache          = {}
local lastNpcName          = nil
local firstGossipPage      = true
local replayingDialog      = false
local replayingAbandon     = false
local abandoningQuestID    = nil
local abandoningQuestTitle = nil
local isActive             = false
local hooksInstalled       = false

local SAFE_POPUPS = {
    CONFIRM_SUMMON            = true,
    RESURRECT                 = true,
    RESURRECT_NO_SICKNESS     = true,
    RESURRECT_NO_TIMER        = true,
    PARTY_INVITE              = true,
    PARTY_INVITE_XREALM       = true,
    CONFIRM_ACCEPT_QUEST      = true,
    GOSSIP_CONFIRM            = true,
    QUEST_ACCEPT              = true,
    ABANDON_QUEST             = true,
    ABANDON_QUEST_WITH_ITEMS  = true,
    LOOT_BIND                 = true,
    EQUIP_BIND                = true,
    USE_BIND                  = true,
    CONFIRM_LOOT_ROLL         = true,
    CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL = true,
}

local CLASS_ARMOR_SUBCLASS = {
    WARRIOR     = 4,
    PALADIN     = 4,
    DEATHKNIGHT = 4,
    HUNTER      = 3,
    SHAMAN      = 3,
    EVOKER      = 3,
    DRUID       = 2,
    ROGUE       = 2,
    MONK        = 2,
    DEMONHUNTER = 2,
    MAGE        = 1,
    PRIEST      = 1,
    WARLOCK     = 1,
}

local function should_automate_quests()
    if not isActive then return false end
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoQuest == false then return false end
    if sync.IsAway and sync.IsAway() then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    if not (multibox and multibox.IsActiveSyncParty and multibox.IsActiveSyncParty()) then return false end
    return true
end

local function current_npc_name()
    if UnitExists and UnitExists("npc") then
        local n = UnitName("npc")
        if n and n ~= "" then
            lastNpcName = n
            return n
        end
    end
    if UnitExists and UnitExists("questnpc") then
        local n = UnitName("questnpc")
        if n and n ~= "" then
            lastNpcName = n
            return n
        end
    end
    return lastNpcName
end

local function broadcast_dialog_choice(verb, npc, id, text, extraItemID, questID)
    if replayingDialog then return end
    if not should_automate_quests() then return end
    local s = sync.GetSettings and sync.GetSettings()
    sync.Broadcast("DELTA_DIALOG", {
        pass = (s and s.passcode ~= "" and s.passcode) or nil,
        v    = verb,
        n    = npc or current_npc_name() or "",
        i    = tonumber(id),
        t    = text or "",
        r    = tonumber(extraItemID) or nil,
        q    = tonumber(questID) or nil,
    }, true, false)
end

local function is_dangerous_single_gossip(text)
    if type(text) ~= "string" or text == "" then return true end
    local lower = string_lower(text)
    if lower:find("home") or lower:find("inn") or lower:find("hearthstone") or lower:find("unlearn") or lower:find("reset") then
        return true
    end
    return false
end

-- ── 1. Smart Quest Reward Scoring & Selection (`Mama/Loot.lua:118-216`) ──────
local function get_expected_armor_subclass()
    local _, classToken = UnitClass and UnitClass("player")
    local base = classToken and CLASS_ARMOR_SUBCLASS[classToken] or 1
    if not sfui.isRetail then
        local lvl = (UnitLevel and UnitLevel("player")) or 1
        if lvl < 40 then
            if base == 4 then return 3 end
            if base == 3 then return 2 end
        end
    end
    return base
end

local function score_quest_reward_choice(choiceIdx)
    local link = _G.GetQuestItemLink and _G.GetQuestItemLink("choice", choiceIdx)
    if not link then return 0, 0, nil, nil end
    local itemID = tonumber(string_match(link, "item:(%d+)"))
    local GetItemInfo = (sfui.common and sfui.common.get_item_info) or _G.GetItemInfo
    local _, _, _, _, _, _, _, _, equipLoc, _, sellPrice, classID, subclassID = GetItemInfo(link)
    sellPrice = tonumber(sellPrice) or 0

    local isUsable = true
    if _G.GetQuestItemInfo then
        local _, _, _, _, usable = _G.GetQuestItemInfo("choice", choiceIdx)
        if usable == false or usable == 0 then
            isUsable = false
        end
    end

    local weaponClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Weapon) or 2
    local armorClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Armor) or 4

    if classID ~= weaponClass and classID ~= armorClass then
        return (isUsable and 2 or 0), sellPrice, itemID, classID
    end

    if not isUsable then
        return 0, sellPrice, itemID, classID
    end

    if equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" or equipLoc == "INVTYPE_HOLDABLE" then
        return 2, sellPrice, itemID, classID
    end

    if classID == armorClass and subclassID and subclassID >= 1 and subclassID <= 4 then
        local wanted = get_expected_armor_subclass()
        if subclassID == wanted then
            return 3, sellPrice, itemID, classID
        elseif subclassID < wanted then
            return 1, sellPrice, itemID, classID
        else
            return 0, sellPrice, itemID, classID
        end
    end

    return 2, sellPrice, itemID, classID
end

local function get_manual_reward_choice()
    if _G.QuestInfoFrame and tonumber(_G.QuestInfoFrame.itemChoice) and tonumber(_G.QuestInfoFrame.itemChoice) > 0 then
        return tonumber(_G.QuestInfoFrame.itemChoice)
    end
    if _G.QuestFrameRewardPanel and tonumber(_G.QuestFrameRewardPanel.itemChoice) and tonumber(_G.QuestFrameRewardPanel.itemChoice) > 0 then
        return tonumber(_G.QuestFrameRewardPanel.itemChoice)
    end
    return nil
end

local function highlight_reward_choice(choiceIdx)
    if not choiceIdx or choiceIdx <= 0 then return end
    local btn = (_G.QuestInfo_GetRewardButton and _G.QuestInfo_GetRewardButton(_G.QuestInfoRewardsFrame, choiceIdx))
        or _G["QuestInfoRewardsFrameQuestInfoItem" .. choiceIdx]
        or _G["QuestRewardItem" .. choiceIdx]
    if btn and _G.QuestInfoItem_OnClick then
        _G.QuestInfoItem_OnClick(btn)
    end
end

-- Returns an unambiguous reward index to auto-pick, or (nil, bestCandidateIdx) if multiple gear choices tie
local function resolve_auto_quest_reward(numChoices, leadRewardItemID)
    if numChoices <= 0 then return nil, nil end
    if numChoices == 1 then return 1, 1 end

    local manual = get_manual_reward_choice()
    if manual and manual >= 1 and manual <= numChoices then
        return manual, manual
    end

    local bestFit = -1
    local bestFitCount = 0
    local bestFitTopHint = 1
    local bestFitTopPrice = -1
    local bestSellIdx = 1
    local bestSellPrice = -1
    local leadMatchIdx = nil
    local leadMatchClassID = nil

    for i = 1, numChoices do
        local fitScore, sellPrice, itemID, classID = score_quest_reward_choice(i)
        if sellPrice > bestSellPrice then
            bestSellPrice = sellPrice
            bestSellIdx = i
        end
        if leadRewardItemID and itemID == leadRewardItemID then
            leadMatchIdx = i
            leadMatchClassID = classID
        end
        if fitScore > bestFit then
            bestFit = fitScore
            bestFitCount = 1
            bestFitTopHint = i
            bestFitTopPrice = sellPrice
        elseif fitScore == bestFit then
            bestFitCount = bestFitCount + 1
            if sellPrice > bestFitTopPrice then
                bestFitTopPrice = sellPrice
                bestFitTopHint = i
            end
        end
    end

    -- 1. If the lead picked a non-weapon/non-armor reward (e.g. bag, box, consumable) offered on our panel, match it
    local weaponClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Weapon) or 2
    local armorClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Armor) or 4
    if leadMatchIdx and leadMatchClassID and leadMatchClassID ~= weaponClass and leadMatchClassID ~= armorClass then
        return leadMatchIdx, leadMatchIdx
    end

    -- 2. If none of the choices are usable gear for this character, pick highest vendor price automatically
    if bestFit <= 0 then
        return bestSellIdx, bestSellIdx
    end

    -- 3. If exactly one choice is the top armor/weapon fit for this character, pick it automatically
    if bestFitCount == 1 then
        return bestFitTopHint, bestFitTopHint
    end

    -- Multiple usable gear choices tied: highlight the highest vendor-value one among them and let user confirm
    return nil, bestFitTopHint
end

-- ── 2. Synchronized Quest Abandon (`Mama/Actions.lua:284-319`) ────────────────
local function capture_abandon_quest()
    if _G.C_QuestLog and _G.C_QuestLog.GetAbandonQuest then
        abandoningQuestID = _G.C_QuestLog.GetAbandonQuest()
        if abandoningQuestID and _G.C_QuestLog.GetTitleForQuestID then
            abandoningQuestTitle = _G.C_QuestLog.GetTitleForQuestID(abandoningQuestID)
        end
    elseif _G.GetAbandonQuestName then
        abandoningQuestTitle = _G.GetAbandonQuestName()
        abandoningQuestID = nil
    end
end

local function is_quest_already_complete(questID, logIndex)
    if questID and _G.C_QuestLog then
        if _G.C_QuestLog.ReadyForTurnIn and _G.C_QuestLog.ReadyForTurnIn(questID) then
            return true
        end
        if _G.C_QuestLog.IsComplete and _G.C_QuestLog.IsComplete(questID) then
            return true
        end
    end
    if questID and _G.IsQuestComplete and _G.IsQuestComplete(questID) then
        return true
    end
    if logIndex and _G.GetQuestLogTitle then
        local _, _, _, _, _, isComplete = _G.GetQuestLogTitle(logIndex)
        if isComplete == 1 or isComplete == true then
            return true
        end
    end
    return false
end

local function handle_incoming_quest_abandon(sender, data)
    if not should_automate_quests() then return end
    local targetID    = tonumber(data.id)
    local targetTitle = data.title

    if _G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries and _G.C_QuestLog.SetAbandonQuest and _G.C_QuestLog.AbandonQuest then
        local numEntries = _G.C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local info = _G.C_QuestLog.GetInfo and _G.C_QuestLog.GetInfo(i)
            if info and not info.isHeader then
                if (targetID and targetID > 0 and info.questID == targetID)
                    or (targetTitle and targetTitle ~= "" and info.title == targetTitle) then
                    if is_quest_already_complete(info.questID, i) then
                        if sfui.common and sfui.common.print then
                            sfui.common.print(string_format("sync: kept completed quest |cff00ffff%s|r (not auto-abandoning).",
                                string_lower(info.title or targetTitle or "quest")))
                        end
                        return
                    end
                    replayingAbandon = true
                    if _G.C_QuestLog.SetSelectedQuest then
                        _G.C_QuestLog.SetSelectedQuest(info.questID)
                    end
                    _G.C_QuestLog.SetAbandonQuest()
                    _G.C_QuestLog.AbandonQuest()
                    replayingAbandon = false
                    if _G.StaticPopup_Hide then
                        _G.StaticPopup_Hide("ABANDON_QUEST")
                        _G.StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
                    end
                    if sfui.common and sfui.common.print then
                        sfui.common.print(string_format("sync: abandoned quest |cff00ffff%s|r (synced with %s).",
                            string_lower(info.title or targetTitle or "quest"), string_lower(multibox.CommandName(sender))))
                    end
                    return
                end
            end
        end
    elseif _G.GetNumQuestLogEntries and _G.GetQuestLogTitle and _G.SelectQuestLogEntry and _G.SetAbandonQuest and _G.AbandonQuest then
        local numEntries = _G.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local title, _, _, isHeader, _, _, _, qID = _G.GetQuestLogTitle(i)
            if not isHeader then
                if (targetID and targetID > 0 and qID == targetID)
                    or (targetTitle and targetTitle ~= "" and title == targetTitle) then
                    if is_quest_already_complete(qID, i) then
                        if sfui.common and sfui.common.print then
                            sfui.common.print(string_format("sync: kept completed quest |cff00ffff%s|r (not auto-abandoning).",
                                string_lower(title or targetTitle or "quest")))
                        end
                        return
                    end
                    replayingAbandon = true
                    _G.SelectQuestLogEntry(i)
                    _G.SetAbandonQuest()
                    _G.AbandonQuest()
                    replayingAbandon = false
                    if _G.StaticPopup_Hide then
                        _G.StaticPopup_Hide("ABANDON_QUEST")
                        _G.StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
                    end
                    if sfui.common and sfui.common.print then
                        sfui.common.print(string_format("sync: abandoned quest |cff00ffff%s|r (synced with %s).",
                            string_lower(title or targetTitle or "quest"), string_lower(multibox.CommandName(sender))))
                    end
                    return
                end
            end
        end
    end
end

-- ── 3. Gossip, Dialog & Multi-Step Turn-In Catch-Up (`Mama/Dialogs.lua`) ──────
local function select_gossip_entry(o)
    local C_GossipInfo = _G.C_GossipInfo
    replayingDialog = true
    if o.gossipOptionID and C_GossipInfo and C_GossipInfo.SelectOption then
        C_GossipInfo.SelectOption(o.gossipOptionID)
    elseif o.orderIndex ~= nil and C_GossipInfo and C_GossipInfo.SelectOptionByIndex then
        C_GossipInfo.SelectOptionByIndex(o.orderIndex)
    end
    replayingDialog = false
    return true
end

local function replay_gossip_option(id, text)
    local C_GossipInfo = _G.C_GossipInfo
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return false end
    local opts = C_GossipInfo.GetOptions()
    if type(opts) ~= "table" or #opts == 0 then return false end
    if id and id > 0 then
        for _, o in ipairs(opts) do
            if o.gossipOptionID == id then
                return select_gossip_entry(o)
            end
        end
    end
    if text and text ~= "" then
        for _, o in ipairs(opts) do
            if o.name == text then
                return select_gossip_entry(o)
            end
        end
    end
    if id ~= nil then
        for idx, o in ipairs(opts) do
            if (o.orderIndex or (idx - 1)) == id then
                return select_gossip_entry(o)
            end
        end
    end
    return false
end

local function replay_quest_pick(verb, id, title)
    local isAvail = (verb == "avail")
    local C_GossipInfo = _G.C_GossipInfo
    if _G.GossipFrame and _G.GossipFrame:IsShown() and C_GossipInfo then
        local list = isAvail and (C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests())
            or (C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests())
        local pick = isAvail and C_GossipInfo.SelectAvailableQuest or C_GossipInfo.SelectActiveQuest
        if type(list) == "table" and pick then
            for idx, q in ipairs(list) do
                if (id and id > 0 and q.questID == id) or (title and title ~= "" and q.title == title) then
                    replayingDialog = true
                    pick(q.questID or idx)
                    replayingDialog = false
                    return true
                end
            end
        end
    end
    if _G.QuestFrameGreetingPanel and _G.QuestFrameGreetingPanel:IsShown() then
        local n = isAvail and (_G.GetNumAvailableQuests and _G.GetNumAvailableQuests() or 0)
            or (_G.GetNumActiveQuests and _G.GetNumActiveQuests() or 0)
        local getTitle = isAvail and _G.GetAvailableTitle or _G.GetActiveTitle
        local pick = isAvail and _G.SelectAvailableQuest or _G.SelectActiveQuest
        if getTitle and pick then
            for i = 1, n do
                local t = getTitle(i)
                if (title and title ~= "" and t == title) or (id and id == i) then
                    replayingDialog = true
                    pick(i)
                    replayingDialog = false
                    return true
                end
            end
        end
    end
    return false
end

local function replay_static_popup(which, buttonIndex)
    if not which or not SAFE_POPUPS[which] then return false end
    local idx = tonumber(buttonIndex) or 1
    local maxDialogs = _G.STATICPOPUP_NUMDIALOGS or 4
    for i = 1, maxDialogs do
        local f = _G["StaticPopup" .. i]
        if f and f:IsShown() and f.which == which then
            replayingDialog = true
            if _G.StaticPopup_OnClick then
                _G.StaticPopup_OnClick(f, idx)
            else
                local btn = f["button" .. idx] or (f.GetButton and f:GetButton(idx))
                if btn and btn:IsShown() and btn:IsEnabled() and btn.Click then
                    btn:Click()
                end
            end
            replayingDialog = false
            return true
        end
    end
    return false
end

local function drain_pending_dialogs()
    if #pendingDialogChoices == 0 then return false end
    local now = (GetTime and GetTime()) or 0

    -- 1. Prune expired entries in-place
    for i = #pendingDialogChoices, 1, -1 do
        local p = pendingDialogChoices[i]
        if not p or (now - (p.at or 0)) > PENDING_SECONDS then
            table_remove(pendingDialogChoices, i)
        end
    end
    if #pendingDialogChoices == 0 then return false end

    local npc = current_npc_name()

    -- 2. Execute at most ONE dialog step per panel transition (re-entrancy safe)
    for idx, p in ipairs(pendingDialogChoices) do
        local sameNPC = (not p.npc or p.npc == "" or not npc or p.npc == npc)

        if p.verb == "popup" then
            if replay_static_popup(p.text, p.id) then
                table_remove(pendingDialogChoices, idx)
                return true
            end
        elseif sameNPC then
            if p.verb == "opt" then
                if replay_gossip_option(p.id, p.text) then
                    table_remove(pendingDialogChoices, idx)
                    return true
                end
            elseif p.verb == "avail" or p.verb == "active" then
                if (_G.GossipFrame and _G.GossipFrame:IsShown()) or (_G.QuestFrameGreetingPanel and _G.QuestFrameGreetingPanel:IsShown()) then
                    if replay_quest_pick(p.verb, p.id, p.text) then
                        table_remove(pendingDialogChoices, idx)
                        return true
                    end
                end
            elseif p.verb == "prog" then
                if _G.QuestFrameProgressPanel and _G.QuestFrameProgressPanel:IsShown() then
                    if _G.IsQuestCompletable and _G.IsQuestCompletable() and _G.CompleteQuest then
                        table_remove(pendingDialogChoices, idx)
                        replayingDialog = true
                        _G.CompleteQuest()
                        replayingDialog = false
                        return true
                    end
                elseif (_G.GossipFrame and _G.GossipFrame:IsShown()) or (_G.QuestFrameGreetingPanel and _G.QuestFrameGreetingPanel:IsShown()) then
                    -- Multi-step catch-up: open the active quest first, keep `prog` queued for QUEST_PROGRESS
                    if replay_quest_pick("active", p.id, p.text) then
                        return true
                    end
                end
            elseif p.verb == "turnin" then
                if _G.QuestFrameRewardPanel and _G.QuestFrameRewardPanel:IsShown() and _G.GetQuestReward then
                    local numChoices = (_G.GetNumQuestChoices and _G.GetNumQuestChoices()) or 0
                    if numChoices <= 1 then
                        table_remove(pendingDialogChoices, idx)
                        replayingDialog = true
                        _G.GetQuestReward(numChoices == 1 and 1 or nil)
                        replayingDialog = false
                        return true
                    else
                        local autoIdx, hintIdx = resolve_auto_quest_reward(numChoices, p.rewardID)
                        table_remove(pendingDialogChoices, idx)
                        if autoIdx then
                            replayingDialog = true
                            _G.GetQuestReward(autoIdx)
                            replayingDialog = false
                            return true
                        elseif hintIdx then
                            highlight_reward_choice(hintIdx)
                            return true
                        end
                    end
                elseif _G.QuestFrameProgressPanel and _G.QuestFrameProgressPanel:IsShown() then
                    -- Multi-step catch-up: step through CompleteQuest(), keep `turnin` queued for QUEST_COMPLETE
                    if _G.IsQuestCompletable and _G.IsQuestCompletable() and _G.CompleteQuest then
                        replayingDialog = true
                        _G.CompleteQuest()
                        replayingDialog = false
                        return true
                    end
                elseif (_G.GossipFrame and _G.GossipFrame:IsShown()) or (_G.QuestFrameGreetingPanel and _G.QuestFrameGreetingPanel:IsShown()) then
                    -- Multi-step catch-up: select the active quest first, keep `turnin` queued
                    if replay_quest_pick("active", p.questID or 0, p.text) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function retry_pending_dialogs()
    if #pendingDialogChoices == 0 then return false end
    if drain_pending_dialogs() then return true end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, drain_pending_dialogs)
    end
    return false
end

local function enqueue_pending_dialog(verb, npc, id, text, rewardID, questID)
    pendingDialogChoices[#pendingDialogChoices + 1] = {
        verb     = verb,
        npc      = npc,
        id       = tonumber(id),
        text     = text,
        rewardID = tonumber(rewardID) or nil,
        questID  = tonumber(questID) or nil,
        at       = (GetTime and GetTime()) or 0,
    }
    retry_pending_dialogs()
end

local function on_gossip_closed()
    firstGossipPage = true
end

local function on_gossip_show()
    current_npc_name()
    local C_GossipInfo = _G.C_GossipInfo
    gossipCache = (C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()) or {}
    local isFirstPage = firstGossipPage
    firstGossipPage = false

    if not should_automate_quests() then return end
    if retry_pending_dialogs() then return end

    -- 1. Turn in completable active quests first
    if C_GossipInfo and C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest then
        local active = C_GossipInfo.GetActiveQuests()
        if type(active) == "table" then
            for _, q in ipairs(active) do
                if q.isComplete and q.questID then
                    C_GossipInfo.SelectActiveQuest(q.questID)
                    return
                end
            end
        end
    elseif _G.GetGossipActiveQuests and _G.SelectGossipActiveQuest then
        local numActive = (_G.GetNumGossipActiveQuests and _G.GetNumGossipActiveQuests()) or 0
        for i = 1, numActive do
            local isComplete = select((i - 1) * 6 + 4, _G.GetGossipActiveQuests())
            if isComplete then
                _G.SelectGossipActiveQuest(i)
                return
            end
        end
    end

    -- 2. Pick up available quests
    if C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
        local avail = C_GossipInfo.GetAvailableQuests()
        if type(avail) == "table" then
            for _, q in ipairs(avail) do
                if not q.isIgnored and q.questID then
                    C_GossipInfo.SelectAvailableQuest(q.questID)
                    return
                end
            end
        end
    elseif _G.GetNumGossipAvailableQuests and _G.SelectGossipAvailableQuest then
        local numAvail = _G.GetNumGossipAvailableQuests() or 0
        if numAvail > 0 then
            _G.SelectGossipAvailableQuest(1)
            return
        end
    end

    -- 3. Single-option non-dangerous gossip auto-select (first page only, next frame so GossipFrame doesn't re-show over TaxiFrame/MerchantFrame)
    if isFirstPage and C_GossipInfo and C_GossipInfo.GetOptions then
        local opts = gossipCache
        local avail = (C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests()) or {}
        local active = (C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()) or {}
        if type(opts) == "table" and #opts == 1 and #avail == 0 and #active == 0 then
            local o = opts[1]
            if o and not o.selectOptionWhenOnlyOption and not o.confirm and not is_dangerous_single_gossip(o.name) then
                local wantID = o.gossipOptionID
                local wantIdx = o.orderIndex
                local selectNow = function()
                    if not should_automate_quests() then return end
                    local nowOpts = C_GossipInfo.GetOptions() or {}
                    if #nowOpts ~= 1 then return end
                    local cur = nowOpts[1]
                    if (wantID and cur.gossipOptionID ~= wantID) or (not wantID and cur.orderIndex ~= wantIdx) then return end
                    local isFollower = not (sync.IsLead and sync.IsLead())
                    if isFollower then replayingDialog = true end
                    if cur.gossipOptionID and C_GossipInfo.SelectOption then
                        C_GossipInfo.SelectOption(cur.gossipOptionID)
                    elseif cur.orderIndex ~= nil and C_GossipInfo.SelectOptionByIndex then
                        C_GossipInfo.SelectOptionByIndex(cur.orderIndex)
                    end
                    if isFollower then replayingDialog = false end
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, selectNow)
                else
                    selectNow()
                end
            end
        end
    end
end

local function on_quest_greeting()
    current_npc_name()
    if not should_automate_quests() then return end
    if retry_pending_dialogs() then return end

    local numActive = (_G.GetNumActiveQuests and _G.GetNumActiveQuests()) or 0
    for i = 1, numActive do
        local _, isComplete = _G.GetActiveTitle(i)
        if isComplete and _G.SelectActiveQuest then
            _G.SelectActiveQuest(i)
            return
        end
    end

    local numAvail = (_G.GetNumAvailableQuests and _G.GetNumAvailableQuests()) or 0
    if numAvail > 0 and _G.SelectAvailableQuest then
        _G.SelectAvailableQuest(1)
    end
end

local function on_quest_detail()
    current_npc_name()
    if not should_automate_quests() then return end
    if _G.QuestGetAutoAccept and _G.QuestGetAutoAccept() then
        if _G.CloseQuest then _G.CloseQuest() end
    elseif _G.AcceptQuest then
        _G.AcceptQuest()
    end
end

local function on_confirm_accept_quest()
    if not should_automate_quests() then return end
    if _G.ConfirmAcceptQuest then
        _G.ConfirmAcceptQuest()
    end
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("CONFIRM_ACCEPT_QUEST")
    end
end

local function on_quest_progress()
    current_npc_name()
    if not should_automate_quests() then return end
    if retry_pending_dialogs() then return end
    if _G.IsQuestCompletable and _G.IsQuestCompletable() and _G.CompleteQuest then
        _G.CompleteQuest()
    end
end

local function on_quest_complete()
    current_npc_name()
    if not should_automate_quests() then return end
    if retry_pending_dialogs() then return end
    local numChoices = (_G.GetNumQuestChoices and _G.GetNumQuestChoices()) or 0
    if numChoices <= 1 and _G.GetQuestReward then
        _G.GetQuestReward(numChoices == 1 and 1 or nil)
    elseif numChoices > 1 then
        local autoIdx, hintIdx = resolve_auto_quest_reward(numChoices, nil)
        if autoIdx and not sync.IsLead() and _G.GetQuestReward then
            _G.GetQuestReward(autoIdx)
        elseif hintIdx then
            highlight_reward_choice(hintIdx)
        end
    end
end

local function on_quest_accepted(_, arg1, arg2)
    if not should_automate_quests() then return end
    local questID = tonumber(arg2) or tonumber(arg1)
    local logIdx  = tonumber(arg2) and tonumber(arg1) or nil

    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, function()
            if not should_automate_quests() then return end
            if questID and sync.GetPartyMissingQuestPeers then
                local missing = sync.GetPartyMissingQuestPeers(questID)
                if not missing or #missing == 0 then return end
            end
            if _G.C_QuestLog and _G.C_QuestLog.PushQuestToParty and questID then
                _G.C_QuestLog.PushQuestToParty(questID)
            elseif _G.QuestLogPushQuest then
                if logIdx and _G.SelectQuestLogEntry then
                    _G.SelectQuestLogEntry(logIdx)
                end
                if not _G.GetQuestLogPushable or _G.GetQuestLogPushable() then
                    _G.QuestLogPushQuest()
                end
            end
        end)
    end
end

local function find_gossip_option_by_id(optionID)
    local C_GossipInfo = _G.C_GossipInfo
    local sources = {
        gossipCache,
        _G.GossipFrame and _G.GossipFrame.gossipOptions,
        C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions(),
    }
    for _, list in ipairs(sources) do
        if type(list) == "table" then
            for _, o in ipairs(list) do
                if o.gossipOptionID == optionID then
                    return o
                end
            end
        end
    end
    return nil
end

local function find_gossip_option_by_index(orderIdx)
    local C_GossipInfo = _G.C_GossipInfo
    local sources = {
        gossipCache,
        _G.GossipFrame and _G.GossipFrame.gossipOptions,
        C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions(),
    }
    for _, list in ipairs(sources) do
        if type(list) == "table" then
            for idx, o in ipairs(list) do
                if (o.orderIndex or (idx - 1)) == orderIdx then
                    return o
                end
            end
        end
    end
    return nil
end

local function install_hooks_once()
    if hooksInstalled then return end
    hooksInstalled = true
    if not _G.hooksecurefunc then return end

    local C_GossipInfo = _G.C_GossipInfo
    if C_GossipInfo then
        if C_GossipInfo.SelectOption then
            _G.hooksecurefunc(C_GossipInfo, "SelectOption", function(optionID)
                if not isActive then return end
                local o = find_gossip_option_by_id(optionID)
                broadcast_dialog_choice("opt", current_npc_name(), optionID, o and o.name or nil)
            end)
        end
        if C_GossipInfo.SelectOptionByIndex then
            _G.hooksecurefunc(C_GossipInfo, "SelectOptionByIndex", function(orderIdx)
                if not isActive then return end
                local o = find_gossip_option_by_index(orderIdx)
                local sendID = (o and o.gossipOptionID and o.gossipOptionID > 0) and o.gossipOptionID or orderIdx
                broadcast_dialog_choice("opt", current_npc_name(), sendID, o and o.name or nil)
            end)
        end
        if C_GossipInfo.SelectAvailableQuest then
            _G.hooksecurefunc(C_GossipInfo, "SelectAvailableQuest", function(questID)
                if not isActive then return end
                local title = nil
                if C_GossipInfo.GetAvailableQuests then
                    for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
                        if q.questID == questID then title = q.title break end
                    end
                end
                broadcast_dialog_choice("avail", current_npc_name(), questID, title)
            end)
        end
        if C_GossipInfo.SelectActiveQuest then
            _G.hooksecurefunc(C_GossipInfo, "SelectActiveQuest", function(questID)
                if not isActive then return end
                local title = nil
                if C_GossipInfo.GetActiveQuests then
                    for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                        if q.questID == questID then title = q.title break end
                    end
                end
                broadcast_dialog_choice("active", current_npc_name(), questID, title)
            end)
        end
    end

    if _G.SelectAvailableQuest then
        _G.hooksecurefunc("SelectAvailableQuest", function(index)
            if not isActive then return end
            local title = _G.GetAvailableTitle and _G.GetAvailableTitle(index)
            broadcast_dialog_choice("avail", current_npc_name(), index, title)
        end)
    end
    if _G.SelectActiveQuest then
        _G.hooksecurefunc("SelectActiveQuest", function(index)
            if not isActive then return end
            local title = _G.GetActiveTitle and _G.GetActiveTitle(index)
            broadcast_dialog_choice("active", current_npc_name(), index, title)
        end)
    end
    if _G.CompleteQuest then
        _G.hooksecurefunc("CompleteQuest", function()
            if not isActive then return end
            local qID = (_G.GetQuestID and _G.GetQuestID()) or 0
            broadcast_dialog_choice("prog", current_npc_name(), qID, _G.GetTitleText and _G.GetTitleText() or "")
        end)
    end
    if _G.GetQuestReward then
        _G.hooksecurefunc("GetQuestReward", function(choiceIdx)
            if not isActive then return end
            local idx = tonumber(choiceIdx) or 0
            local link = (idx > 0 and _G.GetQuestItemLink) and _G.GetQuestItemLink("choice", idx) or nil
            local rewardID = link and tonumber(string_match(link, "item:(%d+)")) or nil
            local qID = (_G.GetQuestID and _G.GetQuestID()) or nil
            broadcast_dialog_choice("turnin", current_npc_name(), idx, _G.GetTitleText and _G.GetTitleText() or "", rewardID, qID)
        end)
    end
    if _G.StaticPopup_OnClick then
        _G.hooksecurefunc("StaticPopup_OnClick", function(dialog, index)
            if not isActive then return end
            local which = dialog and dialog.which
            if which and SAFE_POPUPS[which] then
                broadcast_dialog_choice("popup", "", tonumber(index) or 1, which)
            end
        end)
    end
    if _G.StaticPopup_Show then
        _G.hooksecurefunc("StaticPopup_Show", function()
            if not isActive then return end
            retry_pending_dialogs()
        end)
    end

    -- Synchronized Quest Abandon hooks
    if _G.C_QuestLog and _G.C_QuestLog.SetAbandonQuest and _G.C_QuestLog.AbandonQuest then
        _G.hooksecurefunc(_G.C_QuestLog, "SetAbandonQuest", function()
            if not isActive then return end
            capture_abandon_quest()
        end)
        _G.hooksecurefunc(_G.C_QuestLog, "AbandonQuest", function()
            if not isActive or replayingAbandon then return end
            if not should_automate_quests() then return end
            if not abandoningQuestID and not abandoningQuestTitle then return end
            local s = sync.GetSettings and sync.GetSettings()
            sync.Broadcast("DELTA_QUEST_ABANDON", {
                pass  = (s and s.passcode ~= "" and s.passcode) or nil,
                id    = abandoningQuestID,
                title = abandoningQuestTitle,
            }, true, false)
        end)
    elseif _G.SetAbandonQuest and _G.AbandonQuest then
        _G.hooksecurefunc("SetAbandonQuest", function()
            if not isActive then return end
            capture_abandon_quest()
        end)
        _G.hooksecurefunc("AbandonQuest", function()
            if not isActive or replayingAbandon then return end
            if not should_automate_quests() then return end
            if not abandoningQuestID and not abandoningQuestTitle then return end
            local s = sync.GetSettings and sync.GetSettings()
            sync.Broadcast("DELTA_QUEST_ABANDON", {
                pass  = (s and s.passcode ~= "" and s.passcode) or nil,
                id    = abandoningQuestID,
                title = abandoningQuestTitle,
            }, true, false)
        end)
    end
end

function quests.HandleSyncMessage(sender, msgType, data)
    if not isActive or type(data) ~= "table" then return end
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoQuest == false then return end
    if sync.IsAway and sync.IsAway() then return end

    if msgType == "DELTA_DIALOG" then
        enqueue_pending_dialog(data.v, data.n, data.i, data.t, data.r, data.q)
    elseif msgType == "DELTA_GOSSIP" then
        enqueue_pending_dialog("opt", data.npc, data.id or data.idx, nil, nil)
    elseif msgType == "DELTA_QUEST_ABANDON" then
        handle_incoming_quest_abandon(sender, data)
    end
end

local QUEST_EVENTS = {
    { "GOSSIP_SHOW",          on_gossip_show },
    { "GOSSIP_CLOSED",        on_gossip_closed },
    { "QUEST_GREETING",       on_quest_greeting },
    { "QUEST_DETAIL",         on_quest_detail },
    { "CONFIRM_ACCEPT_QUEST", on_confirm_accept_quest },
    { "QUEST_PROGRESS",       on_quest_progress },
    { "QUEST_COMPLETE",       on_quest_complete },
    { "QUEST_ACCEPTED",       on_quest_accepted },
}

function quests.Enable()
    if isActive then return end
    isActive = true
    install_hooks_once()
    if sfui.events and sfui.events.RegisterEvent then
        for _, entry in ipairs(QUEST_EVENTS) do
            sfui.events.RegisterEvent(entry[1], entry[2])
        end
    end
end

function quests.Disable()
    if not isActive then return end
    isActive = false
    wipe(pendingDialogChoices)
    if sfui.events and sfui.events.UnregisterEvent then
        for _, entry in ipairs(QUEST_EVENTS) do
            sfui.events.UnregisterEvent(entry[1], entry[2])
        end
    end
end

if multibox and multibox.RegisterPartySubmodule then
    multibox.RegisterPartySubmodule(quests)
end

