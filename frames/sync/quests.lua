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
--  Synced-Party Quest, Gossip, Dialog & Abandon Mirroring
--
--  Loaded and active ONLY when in a party with a synced character:
--    1. Synchronized Quest Abandon (`DELTA_QUEST_ABANDON`) with completed-quest
--       safety protection.
--    2. Multi-Step Turn-In Catch-Up (`GossipFrame` -> `QuestFrameProgressPanel`
--       -> `QuestFrameRewardPanel` / `DUIQuestFrame`).
--    3. Gossip / Dialog / Safe StaticPopup Mirroring & Missing-Quest Auto-Share.
--  Local quest automation, smart reward picking, and reward advisor badges are
--  handled independently by `frames/automation/quests.lua`.
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local string_lower = string.lower
local string_format = string.format
local table_remove = table.remove
local wipe = _G.wipe
local GetTime = _G.GetTime
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local IsShiftKeyDown = _G.IsShiftKeyDown
local C_Timer = _G.C_Timer
local issecretvalue = sfui.common.issecretvalue

local PENDING_SECONDS      = 8.0
local pendingDialogChoices = {}
local gossipCache          = {}
local lastNpcName          = nil
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
        if n and not issecretvalue(n) and n ~= "" then
            lastNpcName = n
            return n
        end
    end
    if UnitExists and UnitExists("questnpc") then
        local n = UnitName("questnpc")
        if n and not issecretvalue(n) and n ~= "" then
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

-- ── 1. Synchronized Quest Abandon (`Mama/Actions.lua:284-319`) ────────────────
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

local function perform_abandon(questID, logIndex, titleStr, sender)
    if is_quest_already_complete(questID, logIndex) then
        if sfui.common and sfui.common.print then
            sfui.common.print(string_format("sync: kept completed quest |cff00ffff%s|r (not auto-abandoning).",
                string_lower(titleStr or "quest")))
        end
        return
    end
    replayingAbandon = true
    if _G.C_QuestLog and _G.C_QuestLog.SetSelectedQuest and _G.C_QuestLog.SetAbandonQuest and _G.C_QuestLog.AbandonQuest then
        _G.C_QuestLog.SetSelectedQuest(questID)
        _G.C_QuestLog.SetAbandonQuest()
        _G.C_QuestLog.AbandonQuest()
    elseif logIndex and _G.SelectQuestLogEntry and _G.SetAbandonQuest and _G.AbandonQuest then
        _G.SelectQuestLogEntry(logIndex)
        _G.SetAbandonQuest()
        _G.AbandonQuest()
    end
    replayingAbandon = false
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("ABANDON_QUEST")
        _G.StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
    end
    if sfui.common and sfui.common.print then
        sfui.common.print(string_format("sync: abandoned quest |cff00ffff%s|r (synced with %s).",
            string_lower(titleStr or "quest"), string_lower(multibox.CommandName(sender))))
    end
end

local function handle_incoming_quest_abandon(sender, data)
    if not should_automate_quests() then return end
    local targetID    = tonumber(data.id)
    local targetTitle = data.title

    local qs = sfui.queststate
    if qs then
        local entry = (targetID and targetID > 0 and qs.GetActive and qs.GetActive(targetID))
            or (targetTitle and targetTitle ~= "" and qs.GetActiveByTitle and qs.GetActiveByTitle(targetTitle))
        if entry then
            perform_abandon(entry.questID, entry.logIndex, entry.title or targetTitle, sender)
        end
        return
    end

    if _G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries and _G.C_QuestLog.SetAbandonQuest and _G.C_QuestLog.AbandonQuest then
        local numEntries = _G.C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local info = _G.C_QuestLog.GetInfo and _G.C_QuestLog.GetInfo(i)
            if info and not info.isHeader then
                if (targetID and targetID > 0 and info.questID == targetID)
                    or (targetTitle and targetTitle ~= "" and info.title == targetTitle) then
                    perform_abandon(info.questID, i, info.title or targetTitle, sender)
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
                    perform_abandon(qID, i, title or targetTitle, sender)
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
    if not should_automate_quests() then return false end
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
            local duiFrame = _G.DUIQuestFrame
            local duiShown = duiFrame and duiFrame.IsShown and duiFrame:IsShown()
            local isGossipOpen = (_G.GossipFrame and _G.GossipFrame:IsShown())
                or (_G.QuestFrameGreetingPanel and _G.QuestFrameGreetingPanel:IsShown())
                or (duiShown and (duiFrame.handler == "HandleGossip" or duiFrame.handler == "HandleQuestGreeting"))
            local isProgressOpen = (_G.QuestFrameProgressPanel and _G.QuestFrameProgressPanel:IsShown())
                or (duiShown and duiFrame.handler == "HandleQuestProgress")
            local isRewardOpen = (_G.QuestFrameRewardPanel and _G.QuestFrameRewardPanel:IsShown())
                or (duiShown and duiFrame.handler == "HandleQuestComplete")

            if p.verb == "opt" then
                if replay_gossip_option(p.id, p.text) then
                    table_remove(pendingDialogChoices, idx)
                    return true
                end
            elseif p.verb == "avail" or p.verb == "active" then
                if isGossipOpen then
                    if replay_quest_pick(p.verb, p.id, p.text) then
                        table_remove(pendingDialogChoices, idx)
                        return true
                    end
                end
            elseif p.verb == "prog" then
                if isProgressOpen then
                    if _G.IsQuestCompletable and _G.IsQuestCompletable() and _G.CompleteQuest then
                        table_remove(pendingDialogChoices, idx)
                        replayingDialog = true
                        _G.CompleteQuest()
                        replayingDialog = false
                        return true
                    end
                elseif isGossipOpen then
                    -- Multi-step catch-up: open the active quest first, keep `prog` queued for QUEST_PROGRESS
                    if replay_quest_pick("active", p.id, p.text) then
                        return true
                    end
                end
            elseif p.verb == "turnin" then
                if isRewardOpen and _G.GetQuestReward then
                    table_remove(pendingDialogChoices, idx)
                    local aq = sfui.autoquest
                    if aq and aq.DecorateRewardChoices then
                        aq.DecorateRewardChoices()
                    end
                    if aq and aq.TryAutoCompleteReward then
                        aq.TryAutoCompleteReward(true, false)
                    end
                    return true
                elseif isProgressOpen then
                    -- Multi-step catch-up: step through CompleteQuest(), keep `turnin` queued for QUEST_COMPLETE
                    if _G.IsQuestCompletable and _G.IsQuestCompletable() and _G.CompleteQuest then
                        replayingDialog = true
                        _G.CompleteQuest()
                        replayingDialog = false
                        return true
                    end
                elseif isGossipOpen then
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

local function on_quest_accepted(_, arg1, arg2)
    if not should_automate_quests() then return end
    if not (_G.C_QuestLog and _G.C_QuestLog.PushQuestToParty) then return end
    local questID = tonumber(arg2) or tonumber(arg1)
    if not questID then return end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.6, function()
            if not should_automate_quests() then return end
            if sync.GetPartyMissingQuestPeers then
                local missing = sync.GetPartyMissingQuestPeers(questID)
                if not missing or #missing == 0 then return end
            end
            if _G.C_QuestLog and _G.C_QuestLog.PushQuestToParty then
                _G.C_QuestLog.PushQuestToParty(questID)
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
            local rewardID = sfui.items.get_item_id(link)
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

function quests.IsActive()
    return isActive
end

function quests.IsSyncQuestActive()
    if not isActive then return false end
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoQuest == false then return false end
    if sync.IsAway and sync.IsAway() then return false end
    if not (multibox and multibox.IsActiveSyncParty and multibox.IsActiveSyncParty()) then return false end
    return true
end

function quests.IsSyncRewardEnabled()
    if not quests.IsSyncQuestActive() then return false end
    local s = sync.GetSettings and sync.GetSettings()
    return (s and s.mbAutoQuestReward == true) or false
end

function quests.IsSyncPartyAway()
    if not isActive then return false end
    if not (multibox and multibox.IsActiveSyncParty and multibox.IsActiveSyncParty()) then return false end
    return (sync.IsAway and sync.IsAway()) and true or false
end

function quests.IsSyncFollower()
    if not isActive then return false end
    if not (multibox and multibox.IsActiveSyncParty and multibox.IsActiveSyncParty()) then return false end
    return not (sync.IsLead and sync.IsLead())
end

function quests.OnGossipShow(opts)
    if not isActive then return end
    current_npc_name()
    gossipCache = opts or {}
end

function quests.CaptureNpcName()
    if not isActive then return end
    current_npc_name()
end

function quests.TryReplayPendingDialogs()
    if not isActive then return false end
    return retry_pending_dialogs()
end

function quests.RunSuppressed(fn)
    if type(fn) ~= "function" then return end
    local prev = replayingDialog
    replayingDialog = true
    fn()
    replayingDialog = prev
end

local QUEST_EVENTS = {
    { "QUEST_ACCEPTED", on_quest_accepted },
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
    local aq = sfui.autoquest
    if aq and aq.RefreshEventRegistration then
        aq.RefreshEventRegistration()
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
    local aq = sfui.autoquest
    if aq and aq.RefreshEventRegistration then
        aq.RefreshEventRegistration()
    end
end

if multibox and multibox.RegisterPartySubmodule then
    multibox.RegisterPartySubmodule(quests)
end

