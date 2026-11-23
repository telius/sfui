local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.autoquest = sfui.autoquest or {}
sfui.automation = sfui.automation or {}
sfui.automation.quests = sfui.autoquest

local autoquest = sfui.autoquest

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/automation/quests.lua
--  Standalone Quest Automation, Smart Reward Picker & Quest Reward Advisor
--
--  Works independently of multibox sync mode (solo or any group):
--    1. Auto-Accept, Gossip / Greeting Step-Through, Safe Single-Gossip, and
--       No-Reward Quest Turn-In (`SfuiDB.autoQuest`).
--    2. Smart Auto-Complete & Best Reward Selection (`SfuiDB.autoQuestReward`):
--       picks highest equippable current-spec upgrade (`EvaluateItemUpgrade`)
--       with deterministic tie-breaking, or best vendor gold reward fallback,
--       with async item-cache waiting, 1.55s timeout fallback, money-cost guard,
--       and Shift-hold cancel.
--    3. Visual Quest Reward Advisor Badges (`+X% upg`, `+X% off`, `best gold`)
--       for Blizzard QuestFrame and DialogueUI (`SfuiDB.questRewardAdvisor`).
--    4. Coordinates seamlessly with `sfui.sync.quests` when in an active
--       synced party without duplicate quest actions.
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local select = _G.select
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_lower = string.lower
local string_format = string.format
local wipe = _G.wipe
local GetTime = _G.GetTime
local UnitClass = _G.UnitClass
local UnitLevel = _G.UnitLevel
local IsShiftKeyDown = _G.IsShiftKeyDown
local C_Timer = _G.C_Timer
local issecretvalue = sfui.common and sfui.common.issecretvalue

local firstGossipPage           = true
local dynamicEventsRegistered   = false
local pendingAutoReward         = false
local pendingAutoRewardReplay   = false
local pendingAutoRewardSince    = 0
local pendingAutoRewardQuestKey = nil
local completedAutoRewardKey    = nil
local completedAutoRewardAt     = 0
local shiftCancelledRewardKey   = nil

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

local function get_sync_quests()
    return sfui.sync and sfui.sync.quests or nil
end

local function is_solo_auto_quest_enabled()
    return (_G.SfuiDB and _G.SfuiDB.autoQuest == true) or false
end

local function is_solo_auto_reward_enabled()
    return (_G.SfuiDB and _G.SfuiDB.autoQuestReward == true) or false
end

local function is_sync_active()
    local sq = get_sync_quests()
    return (sq and sq.IsActive and sq.IsActive()) and true or false
end

local function is_sync_auto_quest_enabled()
    local sq = get_sync_quests()
    return (sq and sq.IsSyncQuestActive and sq.IsSyncQuestActive()) and true or false
end

local function is_sync_auto_reward_enabled()
    local sq = get_sync_quests()
    return (sq and sq.IsSyncRewardEnabled and sq.IsSyncRewardEnabled()) and true or false
end

local function is_sync_party_away()
    local sq = get_sync_quests()
    return (sq and sq.IsSyncPartyAway and sq.IsSyncPartyAway()) and true or false
end

local function is_sync_follower()
    local sq = get_sync_quests()
    return (sq and sq.IsSyncFollower and sq.IsSyncFollower()) and true or false
end

local function should_automate_quests()
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    if is_sync_party_away() then return false end
    return is_solo_auto_quest_enabled() or is_sync_auto_quest_enabled()
end

local function should_auto_pick_reward()
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    if is_sync_party_away() then return false end
    return is_solo_auto_reward_enabled() or is_sync_auto_reward_enabled()
end

local function call_with_optional_suppress(suppress, fn)
    local sq = suppress and get_sync_quests() or nil
    if sq and sq.RunSuppressed then
        sq.RunSuppressed(fn)
    else
        fn()
    end
end

local function is_dangerous_single_gossip(text)
    if type(text) ~= "string" or text == "" then return true end
    local lower = string_lower(text)
    if lower:find("home") or lower:find("inn") or lower:find("hearthstone") or lower:find("unlearn") or lower:find("reset") then
        return true
    end
    return false
end

-- ── 1. Smart Quest Reward Scoring & Advisor Badges ────────────────────────────
local function get_expected_armor_subclass()
    local _, classToken
    if UnitClass then
        _, classToken = UnitClass("player")
    end
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
    if not link then return 0, 0, nil, nil, nil end
    local itemID = sfui.items and sfui.items.get_item_id and sfui.items.get_item_id(link)
    local GetItemInfo = (sfui.common and sfui.common.get_item_info) or _G.GetItemInfo
    local _, _, _, _, _, _, _, _, equipLoc, _, sellPrice, classID, subclassID = GetItemInfo(link)
    sellPrice = tonumber(sellPrice) or 0

    local isUsable = true
    local qty = 1
    if _G.GetQuestItemInfo then
        local _, _, q, _, usable = _G.GetQuestItemInfo("choice", choiceIdx)
        qty = math_max(1, tonumber(q) or 1)
        if usable == false or usable == 0 then
            isUsable = false
        end
    end
    sellPrice = sellPrice * qty

    local weaponClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Weapon) or 2
    local armorClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Armor) or 4

    if classID ~= weaponClass and classID ~= armorClass then
        return (isUsable and 2 or 0), sellPrice, itemID, classID, nil
    end

    -- Consult stat-weighted upgrade evaluator first
    if sfui.gear and sfui.gear.EvaluateItemUpgrade then
        local eval = sfui.gear.EvaluateItemUpgrade(link, nil, true)
        if eval and eval.isUpgrade then
            local baseTier = eval.isOffSpec and 50 or 100
            local gain = math_min(49, math_floor((eval.pctGain or 0) * 10 + 0.5) / 10)
            return baseTier + gain, sellPrice, itemID, classID, eval
        end
    end

    if not isUsable then
        return 0, sellPrice, itemID, classID, nil
    end

    if equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" or equipLoc == "INVTYPE_HOLDABLE" then
        return 2, sellPrice, itemID, classID, nil
    end

    if classID == armorClass and subclassID and subclassID >= 1 and subclassID <= 4 then
        local wanted = get_expected_armor_subclass()
        if subclassID == wanted then
            return 3, sellPrice, itemID, classID, nil
        elseif subclassID < wanted then
            return 1, sellPrice, itemID, classID, nil
        else
            return 0, sellPrice, itemID, classID, nil
        end
    end

    return 2, sellPrice, itemID, classID, nil
end

local _advisorBadgesList = {}

local function hide_all_advisor_badges()
    for i = 1, #_advisorBadgesList do
        _advisorBadgesList[i]:Hide()
    end
end

-- Uses explicit OVERLAY sublevels (6/7) rather than BackdropTemplate BACKGROUND so badges render
-- cleanly above DialogueUI's flattenRenderLayers="true" item cards as well as Blizzard's QuestFrame.
local function ensure_button_advisor_badge(btn, isDialogueUI)
    local b = btn._sfuiAdvisorBadge
    if b then
        return b
    end
    b = _G.CreateFrame("Frame", nil, btn)
    b:SetFrameLevel((btn:GetFrameLevel() or 2) + 6)
    b:SetHeight(14)
    if isDialogueUI then
        b:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, 5)
    else
        b:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end

    local border = b:CreateTexture(nil, "OVERLAY", nil, 6)
    border:SetAllPoints()
    border:SetColorTexture(0.25, 0.75, 0.45, 0.90)
    b.border = border

    local bg = b:CreateTexture(nil, "OVERLAY", nil, 7)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.05, 0.06, 0.08, 0.94)
    b.bg = bg

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if fs.SetDrawLayer then
        fs:SetDrawLayer("OVERLAY", 7)
    end
    fs:SetPoint("CENTER", 0, 0)
    b.fs = fs

    btn._sfuiAdvisorBadge = b
    _advisorBadgesList[#_advisorBadgesList + 1] = b

    -- Enable Ctrl-Click recipe/fishing deep-linking on DialogueUI item buttons
    if isDialogueUI and not btn._sfuiCtrlHooked and btn.HookScript then
        btn._sfuiCtrlHooked = true
        btn:HookScript("OnClick", function(self, mouseBtn)
            if mouseBtn == "LeftButton" and _G.IsControlKeyDown and _G.IsControlKeyDown()
                and not (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
                and not (_G.IsAltKeyDown and _G.IsAltKeyDown()) then
                if self.objectType == "item" and sfui.nav and sfui.nav.OpenRecipeOrFishing then
                    local link = (_G.GetQuestItemLink and self.type and self.index and _G.GetQuestItemLink(self.type, self.index)) or nil
                    sfui.nav.OpenRecipeOrFishing(link or self.itemID)
                end
            end
        end)
    end

    return b
end

local function apply_badge_state(btn, isDialogueUI, eval, isBestGold)
    if eval and eval.isUpgrade then
        local badge = ensure_button_advisor_badge(btn, isDialogueUI)
        local pct = (eval.pctGain >= 99.5) and "+upgrade" or string_format("+%.0f%%", eval.pctGain)
        if eval.isOffSpec then
            badge.fs:SetText("|cff66ccff" .. pct .. " off|r")
            badge.border:SetColorTexture(0.35, 0.75, 1.0, 0.88)
        else
            badge.fs:SetText("|cff33ff88" .. pct .. " upg|r")
            badge.border:SetColorTexture(0.20, 0.85, 0.45, 0.92)
        end
        badge:SetWidth(math_max(44, (badge.fs:GetStringWidth() or 36) + 10))
        badge:Show()
    elseif isBestGold then
        local badge = ensure_button_advisor_badge(btn, isDialogueUI)
        badge.fs:SetText("|cffffd100best gold|r")
        badge.border:SetColorTexture(0.95, 0.78, 0.20, 0.88)
        badge:SetWidth(math_max(54, (badge.fs:GetStringWidth() or 44) + 10))
        badge:Show()
    elseif btn._sfuiAdvisorBadge then
        btn._sfuiAdvisorBadge:Hide()
    end
end

local function eval_fixed_quest_reward(rewardIdx)
    if not (sfui.gear and sfui.gear.EvaluateItemUpgrade and _G.GetQuestItemLink) then
        return nil
    end
    local link = _G.GetQuestItemLink("reward", rewardIdx)
    if not link then return nil end
    local GetItemInfo = (sfui.common and sfui.common.get_item_info) or _G.GetItemInfo
    local classID = select(12, GetItemInfo(link))
    local weaponClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Weapon) or 2
    local armorClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Armor) or 4
    if classID ~= weaponClass and classID ~= armorClass then
        return nil
    end
    return sfui.gear.EvaluateItemUpgrade(link, nil, true)
end

local _choiceEvalScratch = {}
local _rewardEvalScratch = {}

local function decorate_quest_reward_choices()
    hide_all_advisor_badges()
    if SfuiDB and SfuiDB.questRewardAdvisor == false then return end

    local numChoices = (_G.GetNumQuestChoices and _G.GetNumQuestChoices()) or 0
    local numRewards = (_G.GetNumQuestRewards and _G.GetNumQuestRewards()) or 0
    if numChoices <= 0 and numRewards <= 0 then return end

    wipe(_choiceEvalScratch)
    wipe(_rewardEvalScratch)

    local bestUpgradeIdx = nil
    local bestUpgradeScore = 0
    local bestSellIdx = nil
    local bestSellPrice = 0

    for i = 1, numChoices do
        local fitScore, sellPrice, _, _, eval = score_quest_reward_choice(i)
        _choiceEvalScratch[i] = eval
        if eval and eval.isUpgrade and fitScore > bestUpgradeScore then
            bestUpgradeScore = fitScore
            bestUpgradeIdx = i
        end
        if sellPrice > bestSellPrice then
            bestSellPrice = sellPrice
            bestSellIdx = i
        end
    end

    for i = 1, numRewards do
        _rewardEvalScratch[i] = eval_fixed_quest_reward(i)
    end

    -- 1. Standard Blizzard QuestInfoRewardsFrame / QuestFrameRewardPanel buttons
    for i = 1, numChoices do
        local btn = (_G.QuestInfo_GetRewardButton and _G.QuestInfo_GetRewardButton(_G.QuestInfoRewardsFrame, i))
            or _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
            or _G["QuestRewardItem" .. i]
        if btn and btn:IsShown() then
            local eval = _choiceEvalScratch[i]
            local isGoldBest = (not bestUpgradeIdx) and (numChoices > 1) and (i == bestSellIdx) and (bestSellPrice > 0)
            apply_badge_state(btn, false, eval, isGoldBest)
        end
    end
    for i = 1, numRewards do
        local btnIdx = numChoices + i
        local btn = (_G.QuestInfo_GetRewardButton and _G.QuestInfo_GetRewardButton(_G.QuestInfoRewardsFrame, btnIdx))
            or _G["QuestInfoRewardsFrameQuestInfoItem" .. btnIdx]
            or _G["QuestRewardItem" .. btnIdx]
        if btn and btn:IsShown() then
            apply_badge_state(btn, false, _rewardEvalScratch[i], false)
        end
    end

    -- 2. DialogueUI (DUIQuestFrame.itemButtonPool) on Forever & Retail
    local duiFrame = _G.DUIQuestFrame
    if duiFrame and duiFrame.IsShown and duiFrame:IsShown() and duiFrame.itemButtonPool and duiFrame.itemButtonPool.ProcessActiveObjects then
        duiFrame.itemButtonPool:ProcessActiveObjects(function(btn)
            if not btn or not btn:IsShown() or btn.objectType ~= "item" then return end
            if btn.type == "choice" and btn.index then
                local i = btn.index
                local eval = _choiceEvalScratch[i]
                local isGoldBest = (not bestUpgradeIdx) and (numChoices > 1) and (i == bestSellIdx) and (bestSellPrice > 0)
                apply_badge_state(btn, true, eval, isGoldBest)
            elseif btn.type == "reward" and btn.index then
                apply_badge_state(btn, true, _rewardEvalScratch[btn.index], false)
            end
        end)
    end
end

-- ── 2. Smart Reward Auto-Selection & Auto-Complete ────────────────────────────
local function has_quest_reward_choice()
    local numChoices = (_G.GetNumQuestChoices and _G.GetNumQuestChoices()) or 0
    if numChoices > 0 then return true end
    local duiFrame = _G.DUIQuestFrame
    if duiFrame and duiFrame.IsShown and duiFrame:IsShown() and duiFrame.chooseItems then
        return true
    end
    return false
end

local function clear_pending_auto_reward()
    pendingAutoReward = false
    pendingAutoRewardReplay = false
    pendingAutoRewardSince = 0
    pendingAutoRewardQuestKey = nil
end

local function get_active_quest_key()
    local qID = (_G.GetQuestID and _G.GetQuestID()) or 0
    if qID and qID > 0 then
        return "id:" .. qID
    end
    local title = _G.GetTitleText and _G.GetTitleText()
    if title and (not issecretvalue or not issecretvalue(title)) and title ~= "" then
        return "t:" .. title
    end
    return "open"
end

local function is_quest_reward_panel_open()
    if _G.QuestFrameRewardPanel and _G.QuestFrameRewardPanel:IsShown() then
        return true
    end
    local duiFrame = _G.DUIQuestFrame
    if duiFrame and duiFrame.IsShown and duiFrame:IsShown() and duiFrame.handler == "HandleQuestComplete" then
        return true
    end
    return false
end

local function is_better_spec_upgrade(candEval, candSell, curEval, curSell)
    if not curEval then return true end
    local candPct = candEval.pctGain or 0
    local curPct  = curEval.pctGain or 0
    if math_abs(candPct - curPct) > 0.05 then
        return candPct > curPct
    end
    local candScore = candEval.scoreDelta or 0
    local curScore  = curEval.scoreDelta or 0
    if math_abs(candScore - curScore) > 0.05 then
        return candScore > curScore
    end
    local candIlvl = candEval.ilvlDelta or 0
    local curIlvl  = curEval.ilvlDelta or 0
    if candIlvl ~= curIlvl then
        return candIlvl > curIlvl
    end
    return (candSell or 0) > (curSell or 0)
end

local function select_best_quest_reward_choice(allowIncompleteCache)
    local numChoices = (_G.GetNumQuestChoices and _G.GetNumQuestChoices()) or 0
    if numChoices <= 0 then
        if has_quest_reward_choice() and not allowIncompleteCache then
            return nil, "pending", nil, nil, nil
        end
        return nil, "ready", nil, nil, "no_choice"
    end

    local GetItemInfo = (sfui.common and sfui.common.get_item_info) or _G.GetItemInfo
    local hasUncached = false

    for i = 1, numChoices do
        local link = _G.GetQuestItemLink and _G.GetQuestItemLink("choice", i)
        local questItemID = nil
        if _G.GetQuestItemInfo then
            questItemID = select(6, _G.GetQuestItemInfo("choice", i))
        end
        local itemName = link and GetItemInfo(link)
        if not link or not itemName then
            local itemID = (sfui.items and sfui.items.get_item_id and sfui.items.get_item_id(link)) or tonumber(questItemID)
            if itemID and sfui.common and sfui.common.request_item_load then
                sfui.common.request_item_load(itemID)
            end
            hasUncached = true
        end
    end

    if hasUncached and not allowIncompleteCache then
        return nil, "pending", nil, nil, nil
    end

    if numChoices == 1 then
        local link = _G.GetQuestItemLink and _G.GetQuestItemLink("choice", 1)
        return 1, "ready", link, nil, "single"
    end

    local activeSpecID = sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id()
    if not activeSpecID or activeSpecID == 0 then
        activeSpecID = nil
    end

    local weaponClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Weapon) or 2
    local armorClass  = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Armor) or 4
    local projClass   = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Projectile) or 6

    local bestUpgradeIdx  = nil
    local bestUpgradeEval = nil
    local bestUpgradeSell = -1
    local bestUpgradeLink = nil
    local bestGoldIdx     = nil
    local bestGoldSell    = -1
    local bestGoldLink    = nil

    for i = 1, numChoices do
        local link = _G.GetQuestItemLink and _G.GetQuestItemLink("choice", i)
        local qty = 1
        local usable = true
        if _G.GetQuestItemInfo then
            local _, _, q, _, u = _G.GetQuestItemInfo("choice", i)
            qty = math_max(1, tonumber(q) or 1)
            if u == false or u == 0 then
                usable = false
            end
        end

        local equipLoc, sellPrice, classID
        if link then
            local _, _, _, _, _, _, _, _, eqLoc, _, sp, cID = GetItemInfo(link)
            equipLoc = eqLoc
            sellPrice = (tonumber(sp) or 0) * qty
            classID = cID
        else
            sellPrice = 0
        end

        if sellPrice > bestGoldSell then
            bestGoldSell = sellPrice
            bestGoldIdx = i
            bestGoldLink = link
        end

        local isEquippableClass = (classID == weaponClass or classID == armorClass or (not sfui.isRetail and classID == projClass))
        local isEquippableLoc = equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and equipLoc ~= "INVTYPE_BAG"
        if link and usable and isEquippableClass and isEquippableLoc and activeSpecID and sfui.gear and sfui.gear.EvaluateItemUpgrade then
            local eval = sfui.gear.EvaluateItemUpgrade(link, activeSpecID, false)
            if eval and eval.isUpgrade and not eval.isOffSpec then
                if is_better_spec_upgrade(eval, sellPrice, bestUpgradeEval, bestUpgradeSell) then
                    bestUpgradeIdx = i
                    bestUpgradeEval = eval
                    bestUpgradeSell = sellPrice
                    bestUpgradeLink = link
                end
            end
        end
    end

    if bestUpgradeIdx then
        return bestUpgradeIdx, "ready", bestUpgradeLink, bestUpgradeEval, "upgrade"
    end

    local fallbackIdx = bestGoldIdx or 1
    local fallbackLink = bestGoldLink or (_G.GetQuestItemLink and _G.GetQuestItemLink("choice", fallbackIdx)) or nil
    return fallbackIdx, "ready", fallbackLink, nil, "gold"
end

local function try_auto_complete_quest_reward(isReplay, forceTimeout)
    local qKey = get_active_quest_key()
    if IsShiftKeyDown and IsShiftKeyDown() then
        shiftCancelledRewardKey = qKey
        clear_pending_auto_reward()
        return false
    end
    if shiftCancelledRewardKey and shiftCancelledRewardKey == qKey then
        clear_pending_auto_reward()
        return false
    end

    if is_sync_party_away() or not _G.GetQuestReward then
        clear_pending_auto_reward()
        return false
    end

    local canAutoQuest  = should_automate_quests()
    local canAutoReward = should_auto_pick_reward()
    if not canAutoQuest and not canAutoReward then
        clear_pending_auto_reward()
        return false
    end

    if _G.GetQuestMoneyToGet and (_G.GetQuestMoneyToGet() or 0) > 0 then
        clear_pending_auto_reward()
        return false
    end

    local now = (GetTime and GetTime()) or 0
    if completedAutoRewardKey and completedAutoRewardKey == qKey and (now - completedAutoRewardAt) < 1.5 then
        clear_pending_auto_reward()
        return false
    end

    if not canAutoReward then
        local numRewards = (_G.GetNumQuestRewards and _G.GetNumQuestRewards()) or 0
        clear_pending_auto_reward()
        if canAutoQuest and not has_quest_reward_choice() and numRewards == 0 then
            completedAutoRewardKey = qKey
            completedAutoRewardAt = now
            call_with_optional_suppress(isReplay, function()
                _G.GetQuestReward(nil)
            end)
            return true
        end
        return false
    end

    if pendingAutoReward and pendingAutoRewardQuestKey and pendingAutoRewardQuestKey ~= qKey then
        clear_pending_auto_reward()
    end
    if not pendingAutoReward then
        pendingAutoRewardSince = now
        pendingAutoRewardQuestKey = qKey
    end
    if isReplay then
        pendingAutoRewardReplay = true
    end

    local timedOut = (forceTimeout == true) or ((now - (pendingAutoRewardSince or now)) >= 1.45)
    local choiceIdx, status, chosenLink, chosenEval, reason = select_best_quest_reward_choice(timedOut)
    if status == "pending" then
        pendingAutoReward = true
        if C_Timer and C_Timer.After then
            local expectedKey = qKey
            C_Timer.After(1.55, function()
                if not pendingAutoReward or pendingAutoRewardQuestKey ~= expectedKey then
                    return
                end
                if is_quest_reward_panel_open() then
                    try_auto_complete_quest_reward(pendingAutoRewardReplay, true)
                else
                    clear_pending_auto_reward()
                end
            end)
        end
        return false
    end

    local replayFlag = isReplay or pendingAutoRewardReplay
    clear_pending_auto_reward()
    completedAutoRewardKey = qKey
    completedAutoRewardAt = now

    if _G.QuestInfoFrame then
        _G.QuestInfoFrame.itemChoice = choiceIdx or 0
    end
    if _G.QuestFrameRewardPanel then
        _G.QuestFrameRewardPanel.itemChoice = choiceIdx or 0
    end

    local numChoices = (_G.GetNumQuestChoices and _G.GetNumQuestChoices()) or 0
    if numChoices > 1 and chosenLink and sfui.common and sfui.common.print then
        local tag = is_solo_auto_reward_enabled() and "quest" or "sync"
        if reason == "upgrade" and chosenEval then
            local pct = (chosenEval.pctGain >= 99.5) and "+upgrade" or string_format("+%.0f%%", chosenEval.pctGain)
            sfui.common.print(string_format("%s: auto-picked spec upgrade %s (|cff33ff88%s|r).", tag, chosenLink, pct))
        elseif reason == "gold" then
            sfui.common.print(string_format("%s: auto-picked best gold reward %s.", tag, chosenLink))
        end
    end

    call_with_optional_suppress(replayFlag, function()
        _G.GetQuestReward(choiceIdx)
    end)
    return true
end

-- ── 3. Quest & Gossip Event Handlers ──────────────────────────────────────────
local function on_gossip_closed()
    firstGossipPage = true
end

local function on_gossip_show()
    local C_GossipInfo = _G.C_GossipInfo
    local opts = (C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.GetOptions()) or {}
    local sq = get_sync_quests()
    if sq and sq.OnGossipShow then
        sq.OnGossipShow(opts)
    end

    local isFirstPage = firstGossipPage
    firstGossipPage = false

    if not should_automate_quests() then return end
    if sq and sq.TryReplayPendingDialogs and sq.TryReplayPendingDialogs() then return end

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
                    call_with_optional_suppress(is_sync_follower(), function()
                        if cur.gossipOptionID and C_GossipInfo.SelectOption then
                            C_GossipInfo.SelectOption(cur.gossipOptionID)
                        elseif cur.orderIndex ~= nil and C_GossipInfo.SelectOptionByIndex then
                            C_GossipInfo.SelectOptionByIndex(cur.orderIndex)
                        end
                    end)
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
    local sq = get_sync_quests()
    if sq and sq.CaptureNpcName then
        sq.CaptureNpcName()
    end

    if not should_automate_quests() then return end
    if sq and sq.TryReplayPendingDialogs and sq.TryReplayPendingDialogs() then return end

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
    local sq = get_sync_quests()
    if sq and sq.CaptureNpcName then
        sq.CaptureNpcName()
    end
    decorate_quest_reward_choices()

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
    local sq = get_sync_quests()
    if sq and sq.CaptureNpcName then
        sq.CaptureNpcName()
    end

    if not should_automate_quests() then return end
    if sq and sq.TryReplayPendingDialogs and sq.TryReplayPendingDialogs() then return end

    if _G.IsQuestCompletable and _G.IsQuestCompletable() and _G.CompleteQuest then
        _G.CompleteQuest()
    end
end

local function on_quest_complete()
    local sq = get_sync_quests()
    if sq and sq.CaptureNpcName then
        sq.CaptureNpcName()
    end

    clear_pending_auto_reward()
    decorate_quest_reward_choices()

    local qKey = get_active_quest_key()
    if IsShiftKeyDown and IsShiftKeyDown() then
        shiftCancelledRewardKey = qKey
    elseif shiftCancelledRewardKey ~= qKey then
        shiftCancelledRewardKey = nil
    end

    if not should_automate_quests() and not should_auto_pick_reward() then
        return
    end
    if sq and sq.TryReplayPendingDialogs and sq.TryReplayPendingDialogs() then return end

    try_auto_complete_quest_reward(false, false)
end

local function on_modifier_state_changed(_, key, down)
    if down == 1 and (key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT") then
        if pendingAutoReward or is_quest_reward_panel_open() then
            shiftCancelledRewardKey = get_active_quest_key()
            clear_pending_auto_reward()
        end
    end
end

-- ── 4. Event Wiring, DialogueUI Hooks & Module Lifecycle ──────────────────────
local DYNAMIC_EVENTS = {
    { "GOSSIP_SHOW",            on_gossip_show },
    { "GOSSIP_CLOSED",          on_gossip_closed },
    { "QUEST_GREETING",         on_quest_greeting },
    { "CONFIRM_ACCEPT_QUEST",   on_confirm_accept_quest },
    { "QUEST_PROGRESS",         on_quest_progress },
    { "MODIFIER_STATE_CHANGED", on_modifier_state_changed },
}

local function refresh_event_registration()
    local want = is_solo_auto_quest_enabled()
        or is_solo_auto_reward_enabled()
        or is_sync_active()
    if want == dynamicEventsRegistered then
        return
    end
    dynamicEventsRegistered = want
    if want then
        if sfui.events and sfui.events.RegisterEvent then
            for _, entry in ipairs(DYNAMIC_EVENTS) do
                sfui.events.RegisterEvent(entry[1], entry[2])
            end
        end
    else
        clear_pending_auto_reward()
        completedAutoRewardKey = nil
        shiftCancelledRewardKey = nil
        if sfui.events and sfui.events.UnregisterEvent then
            for _, entry in ipairs(DYNAMIC_EVENTS) do
                sfui.events.UnregisterEvent(entry[1], entry[2])
            end
        end
    end
end

local _dialogueUIHooked = false

local function is_any_quest_dialog_open()
    if _G.DUIQuestFrame and _G.DUIQuestFrame.IsShown and _G.DUIQuestFrame:IsShown() then
        return true
    end
    if _G.QuestFrame and _G.QuestFrame.IsShown and _G.QuestFrame:IsShown() then
        return true
    end
    return false
end

local function refresh_open_quest_advisor()
    if not is_any_quest_dialog_open() then return end
    decorate_quest_reward_choices()
    if pendingAutoReward and is_quest_reward_panel_open() then
        try_auto_complete_quest_reward(pendingAutoRewardReplay, false)
    end
end

local function hook_dialogue_ui()
    if _dialogueUIHooked then return end
    local duiFrame = _G.DUIQuestFrame
    if not (duiFrame and _G.hooksecurefunc) then return end
    _dialogueUIHooked = true

    if duiFrame.HandleQuestDetail then
        _G.hooksecurefunc(duiFrame, "HandleQuestDetail", decorate_quest_reward_choices)
    end
    if duiFrame.HandleQuestComplete then
        _G.hooksecurefunc(duiFrame, "HandleQuestComplete", decorate_quest_reward_choices)
    end
    if duiFrame.ReleaseAllObjects then
        _G.hooksecurefunc(duiFrame, "ReleaseAllObjects", hide_all_advisor_badges)
    end
    if duiFrame.HookScript then
        duiFrame:HookScript("OnHide", hide_all_advisor_badges)
    end
end

hook_dialogue_ui()

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        hook_dialogue_ui()
        refresh_event_registration()
    end)
    sfui.events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if loadedAddon == "DialogueUI" then
            hook_dialogue_ui()
        end
    end)
    sfui.events.RegisterEvent("QUEST_DETAIL", on_quest_detail)
    sfui.events.RegisterEvent("QUEST_COMPLETE", on_quest_complete)
    sfui.events.RegisterEvent("QUEST_ITEM_UPDATE", function()
        if sfui.common and sfui.common.debounce then
            sfui.common.debounce("quest_advisor_item_update", 0.06, refresh_open_quest_advisor)
        else
            refresh_open_quest_advisor()
        end
    end)
    sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not is_any_quest_dialog_open() then return end
        if sfui.common and sfui.common.debounce then
            sfui.common.debounce("quest_advisor_item_info", 0.08, refresh_open_quest_advisor)
        else
            refresh_open_quest_advisor()
        end
    end)
    sfui.events.RegisterEvent("QUEST_FINISHED", function()
        clear_pending_auto_reward()
        completedAutoRewardKey = nil
        shiftCancelledRewardKey = nil
        hide_all_advisor_badges()
    end)
end

autoquest.DecorateRewardChoices    = decorate_quest_reward_choices
autoquest.HideAdvisorBadges        = hide_all_advisor_badges
autoquest.SelectBestRewardChoice   = select_best_quest_reward_choice
autoquest.TryAutoCompleteReward    = try_auto_complete_quest_reward
autoquest.ClearPendingReward       = clear_pending_auto_reward
autoquest.RefreshEventRegistration = refresh_event_registration

function autoquest.RefreshBadges()
    if is_any_quest_dialog_open() then
        decorate_quest_reward_choices()
    else
        hide_all_advisor_badges()
    end
end

function autoquest.OnInit()
    if _G.SfuiDB then
        if _G.SfuiDB.autoQuest == nil then _G.SfuiDB.autoQuest = false end
        if _G.SfuiDB.autoQuestReward == nil then _G.SfuiDB.autoQuestReward = false end
        if _G.SfuiDB.questRewardAdvisor == nil then _G.SfuiDB.questRewardAdvisor = true end
    end
end

function autoquest.OnEnable()
    autoquest.OnInit()
    hook_dialogue_ui()
    refresh_event_registration()
end

function autoquest.OnSettingsChanged()
    refresh_event_registration()
    autoquest.RefreshBadges()
end

local _autoquestDebug = {}
function autoquest.GetDebugInfo()
    _autoquestDebug.autoQuest          = is_solo_auto_quest_enabled()
    _autoquestDebug.autoQuestReward    = is_solo_auto_reward_enabled()
    _autoquestDebug.questRewardAdvisor = (_G.SfuiDB and _G.SfuiDB.questRewardAdvisor ~= false) or false
    _autoquestDebug.eventsRegistered   = dynamicEventsRegistered
    _autoquestDebug.pendingAutoReward  = pendingAutoReward
    return _autoquestDebug
end

if sfui.RegisterModule then
    sfui.RegisterModule("autoquest", autoquest)
end
