local addonName, addon = ...
sfui = sfui or {}
sfui.alts = sfui.alts or {}
sfui.alts.mail = sfui.alts.mail or {}

local mail = sfui.alts.mail
local common = sfui.common

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/alts/mail_engine.lua
--  Mailbox dispatch automation, rate-limiting ticker, and network state machine
-- ══════════════════════════════════════════════════════════════════════════════

local C_Timer = _G.C_Timer
local C_Container = _G.C_Container
local SendMail = _G.SendMail
local ClearSendMail = _G.ClearSendMail
local HasSendMailItem = _G.HasSendMailItem
local InCombatLockdown = _G.InCombatLockdown
local GetRealmName = _G.GetRealmName
local GetInboxNumItems = _G.GetInboxNumItems
local GetInboxHeaderInfo = _G.GetInboxHeaderInfo
local GetInboxItem = _G.GetInboxItem
local HasInboxItem = _G.HasInboxItem
local TakeInboxMoney = _G.TakeInboxMoney
local TakeInboxItem = _G.TakeInboxItem
local C_Mail = _G.C_Mail

local _isDispatching = false
local _dispatchQueue = {}
local _currentLetterIndex = 0
local _totalLetters = 0
local _progressCallback = nil
local _completeCallback = nil
local _safetyTimer = nil
local _stepTimer = nil
local _waitingForSuccess = false

local _isCollectingInbox = false
local _inboxMailIndex = 1
local _inboxAttachIndex = 16
local _inboxTotalMail = 0
local _inboxStepTimer = nil
local _inboxSafetyTimer = nil
local _inboxFailedItems = {}
local _inboxProgressCallback = nil
local _inboxCompleteCallback = nil
local _secureTransferActive = false

local ATTACHMENTS_MAX_SEND = _G.ATTACHMENTS_MAX_SEND or 12
local ATTACHMENTS_MAX_RECEIVE = _G.ATTACHMENTS_MAX_RECEIVE or 16
local INTER_LETTER_DELAY = 0.9
local INBOX_RETRIEVAL_DELAY = 0.18

--- Check if the mail engine is actively dispatching letters
--- @return boolean isDispatching
function mail.IsDispatching()
    return _isDispatching
end

--- Get current dispatch progress status
--- @return boolean isDispatching, number current, number total, string recipient
function mail.GetDispatchProgress()
    if not _isDispatching or #_dispatchQueue == 0 then
        return false, 0, 0, ""
    end
    local currentTask = _dispatchQueue[1]
    return true, _currentLetterIndex, _totalLetters, (currentTask and currentTask.recipient) or ""
end

local function SetStepTimer(delay, callback)
    if _stepTimer then
        if _stepTimer.Cancel then
            _stepTimer:Cancel()
        end
        _stepTimer = nil
    end
    if delay and callback and C_Timer then
        local timerFn = C_Timer.NewTimer or C_Timer.After
        _stepTimer = timerFn(delay, callback)
    end
end

local function SetSafetyTimer(delay, callback)
    if _safetyTimer then
        if _safetyTimer.Cancel then
            _safetyTimer:Cancel()
        end
        _safetyTimer = nil
    end
    if delay and callback and C_Timer then
        local timerFn = C_Timer.NewTimer or C_Timer.After
        _safetyTimer = timerFn(delay, callback)
    end
end

--- Cancel active timers
local function CancelTimers()
    SetSafetyTimer(nil)
    SetStepTimer(nil)
end

--- Count how many items are currently attached to the SendMail frame
--- @return number attachedCount
local function GetAttachedItemCount()
    local count = 0
    for i = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem and HasSendMailItem(i) then
            count = count + 1
        end
    end
    return count
end

--- Search player bags for an unlocked item matching itemID if it shifted
--- @param itemID number
--- @return number|nil bag, number|nil slot
local function FindItemInBags(itemID)
    if not C_Container or not itemID then return nil, nil end
    for bag = 0, mail.GetLastBagIndex() do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id == itemID then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and not info.isLocked then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

--- Check if Blizzard confirmation dialog is awaiting player input
--- @return boolean isWaiting
local function IsConfirmationPopupWaiting()
    if _secureTransferActive then return true end
    local spVisible = _G.StaticPopup_Visible
    if spVisible then
        return spVisible("CONFIRM_MAIL_ITEM_UNREFUNDABLE") ~= nil or spVisible("SEND_MONEY") ~= nil
    end
    for i = 1, 4 do
        local sp = _G["StaticPopup" .. i]
        if sp and sp.IsShown and sp:IsShown() then
            local which = sp.which
            if which == "CONFIRM_MAIL_ITEM_UNREFUNDABLE" or which == "SEND_MONEY" then
                return true
            end
        end
    end
    return false
end

--- Cancel active mail dispatch
--- @param reason string?
function mail.CancelDispatch(reason)
    if not _isDispatching then return end
    _isDispatching = false
    _waitingForSuccess = false
    _secureTransferActive = false
    _dispatchQueue = {}
    _currentLetterIndex = 0
    _totalLetters = 0

    CancelTimers()

    if ClearSendMail then
        ClearSendMail()
    end

    if reason and common and common.print then
        common.print(string.format("|cffff9900alts mail dispatch aborted: %s.|r", reason))
    end

    if _completeCallback then
        _completeCallback(false, reason or "cancelled")
        _completeCallback = nil
    end
    _progressCallback = nil
end

--- Switch to the Send Mail tab on Blizzard MailFrame
--- @return boolean isReady
local function EnsureSendMailTab()
    if not _G.MailFrame or not _G.MailFrame:IsShown() then return false end
    if _G.SendMailFrame and _G.SendMailFrame:IsShown() then return true end

    if _G.MailFrameTab2 and _G.MailFrameTab2:IsShown() then
        _G.MailFrameTab2:Click()
        return true
    elseif _G.MailFrameTab_OnClick then
        _G.MailFrameTab_OnClick(nil, 2)
        return true
    end
    return false
end

-- Forward declarations for letter state machine
local SendNextLetter
local PrepareLetterForAttachment
local AttachItemStep
local CheckItemAttached
local VerifyAndDispatchLetter

--- Verify and send letter once all attachments are confirmed
--- @param letter table
--- @param verifyAttempt number?
function VerifyAndDispatchLetter(letter, verifyAttempt)
    if not _isDispatching then return end
    verifyAttempt = verifyAttempt or 0

    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        mail.CancelDispatch("mailbox closed")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        mail.CancelDispatch("combat entered")
        return
    end

    if #letter.items == 0 then
        table.remove(_dispatchQueue, 1)
        SetStepTimer(0.3, SendNextLetter)
        return
    end

    -- Verify all items are confirmed attached in SendMail frame slots
    local attachedCount = GetAttachedItemCount()
    if attachedCount < #letter.items then
        if verifyAttempt < 15 then
            -- UI attachment still registering, wait a micro-tick and re-verify
            SetStepTimer(0.08, function()
                VerifyAndDispatchLetter(letter, verifyAttempt + 1)
            end)
            return
        else
            -- Attachment failure: never send incomplete letters
            if common and common.print then
                common.print(string.format("|cffff3333dispatch aborted: attached %d of %d items for %s.|r", attachedCount, #letter.items, letter.recipient))
            end
            if ClearSendMail then ClearSendMail() end
            mail.CancelDispatch("attachment verification failed")
            return
        end
    end

    -- Confirm recipient and subject edit boxes are populated
    if _G.SendMailNameEditBox and _G.SendMailNameEditBox:GetText() ~= letter.recipient then
        _G.SendMailNameEditBox:SetText(letter.recipient)
    end
    if _G.SendMailSubjectEditBox and (_G.SendMailSubjectEditBox:GetText() == "" or _G.SendMailSubjectEditBox:GetText() ~= (letter.subject or "sfui: alts mail")) then
        _G.SendMailSubjectEditBox:SetText(letter.subject or "sfui: alts mail")
    end
    if _G.SendMailBodyEditBox then
        _G.SendMailBodyEditBox:SetText("")
    end

    -- Update Blizzard send button validation state
    if _G.SendMailFrame_CanSend then
        _G.SendMailFrame_CanSend()
    end

    -- Arm safety timeout with extension if player is responding to a confirmation dialog
    local function ScheduleSafety()
        SetSafetyTimer(8.0, function()
            if not _isDispatching or #_dispatchQueue == 0 or _dispatchQueue[1] ~= letter then return end

            -- Extend timeout if Blizzard confirmation dialog is awaiting player input
            if IsConfirmationPopupWaiting() then
                ScheduleSafety()
                return
            end

            if common and common.print then
                common.print(string.format("|cffff9900mail confirmation timeout for %s, continuing...|r", letter.recipient))
            end
            _waitingForSuccess = false
            table.remove(_dispatchQueue, 1)
            if ClearSendMail then ClearSendMail() end
            SetStepTimer(INTER_LETTER_DELAY, SendNextLetter)
        end)
    end
    ScheduleSafety()

    _waitingForSuccess = true

    -- Dispatch letter
    if SendMail then
        SendMail(letter.recipient, letter.subject or "sfui: alts mail", "")
    elseif _G.SendMailMailButton and _G.SendMailMailButton:IsEnabled() then
        _G.SendMailMailButton:Click()
    end
end

--- Check if the item has successfully attached to the expected send mail slot
--- @param letter table
--- @param itemIndex number
--- @param retryCount number
function CheckItemAttached(letter, itemIndex, retryCount)
    if not _isDispatching then return end

    local isAttached = (HasSendMailItem and HasSendMailItem(itemIndex)) or (GetAttachedItemCount() >= itemIndex)
    if isAttached then
        -- Attachment confirmed, advance to next item
        SetStepTimer(0.04, function()
            AttachItemStep(letter, itemIndex + 1, 0)
        end)
    else
        -- Not yet attached, retry check/action
        SetStepTimer(0.08, function()
            AttachItemStep(letter, itemIndex, retryCount + 1)
        end)
    end
end

--- Attach a specific item from the letter into the SendMail frame with verification
--- @param letter table
--- @param itemIndex number
--- @param retryCount number
function AttachItemStep(letter, itemIndex, retryCount)
    if not _isDispatching then return end

    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        mail.CancelDispatch("mailbox closed")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        mail.CancelDispatch("combat entered")
        return
    end

    -- If all items in this letter are processed, proceed to pre-send verification
    if itemIndex > #letter.items then
        SetStepTimer(0.08, function()
            VerifyAndDispatchLetter(letter, 0)
        end)
        return
    end

    -- Safeguard: if single item cannot attach after ~2.5 seconds of attempts
    if retryCount > 25 then
        local it = letter.items[itemIndex]
        if common and common.print then
            common.print(string.format("|cffff3333failed to attach item %s for %s (bag slot locked or busy).|r", (it and it.link) or "item", letter.recipient))
        end
        table.remove(letter.items, itemIndex)
        if #letter.items == 0 then
            table.remove(_dispatchQueue, 1)
            if ClearSendMail then ClearSendMail() end
            SetStepTimer(INTER_LETTER_DELAY, SendNextLetter)
        else
            SetStepTimer(0.1, function()
                AttachItemStep(letter, itemIndex, 0)
            end)
        end
        return
    end

    -- If slot is already populated, advance immediately
    if HasSendMailItem and HasSendMailItem(itemIndex) then
        SetStepTimer(0.04, function()
            AttachItemStep(letter, itemIndex + 1, 0)
        end)
        return
    end

    local it = letter.items[itemIndex]
    if not it or not C_Container then
        SetStepTimer(0.04, function()
            AttachItemStep(letter, itemIndex + 1, 0)
        end)
        return
    end

    -- Verify item position in bags
    local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
    if not info or info.itemID ~= it.itemID then
        local newBag, newSlot = FindItemInBags(it.itemID)
        if newBag then
            it.bag = newBag
            it.slot = newSlot
            info = C_Container.GetContainerItemInfo(it.bag, it.slot)
        end
    end

    -- If item was lost, destroyed, or consumed, skip it
    if not info then
        if common and common.print then
            common.print(string.format("|cffff9900item %s not found in bags, skipping.|r", it.link or ("item:" .. tostring(it.itemID))))
        end
        table.remove(letter.items, itemIndex)
        SetStepTimer(0.04, function()
            AttachItemStep(letter, itemIndex, 0)
        end)
        return
    end

    -- If bag slot is locked (server transaction in progress), wait and retry
    if info.isLocked then
        SetStepTimer(0.1, function()
            AttachItemStep(letter, itemIndex, retryCount + 1)
        end)
        return
    end

    -- Bag item is unlocked and ready: attach it
    C_Container.UseContainerItem(it.bag, it.slot)

    -- Wait micro-delay to let the client register the attachment
    SetStepTimer(0.08, function()
        CheckItemAttached(letter, itemIndex, retryCount)
    end)
end

--- Prepare letter by clearing prior frame state and ensuring all items are unlocked
--- @param letter table
--- @param prepAttempt number?
function PrepareLetterForAttachment(letter, prepAttempt)
    if not _isDispatching then return end
    prepAttempt = prepAttempt or 0

    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        mail.CancelDispatch("mailbox closed")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        mail.CancelDispatch("combat entered")
        return
    end

    if prepAttempt > 35 then
        if common and common.print then
            common.print(string.format("|cffff3333failed waiting for items to unlock for %s, skipping.|r", letter.recipient))
        end
        table.remove(_dispatchQueue, 1)
        if ClearSendMail then ClearSendMail() end
        SetStepTimer(INTER_LETTER_DELAY, SendNextLetter)
        return
    end

    -- Ensure any leftover attachments from previous letter are cleared
    if GetAttachedItemCount() > 0 then
        if ClearSendMail then ClearSendMail() end
        SetStepTimer(0.1, function()
            PrepareLetterForAttachment(letter, prepAttempt + 1)
        end)
        return
    end

    -- Ensure all items for this letter are present and completely unlocked in bags
    local anyLocked = false
    for _, it in ipairs(letter.items) do
        local info = C_Container.GetContainerItemInfo(it.bag, it.slot)
        if not info or info.itemID ~= it.itemID then
            local newBag, newSlot = FindItemInBags(it.itemID)
            if newBag then
                it.bag = newBag
                it.slot = newSlot
                info = C_Container.GetContainerItemInfo(it.bag, it.slot)
            end
        end
        if info and info.isLocked then
            anyLocked = true
            break
        end
    end

    if anyLocked then
        SetStepTimer(0.12, function()
            PrepareLetterForAttachment(letter, prepAttempt + 1)
        end)
        return
    end

    -- Set recipient and subject edit boxes
    if _G.SendMailNameEditBox then
        _G.SendMailNameEditBox:SetText(letter.recipient)
    end
    if _G.SendMailSubjectEditBox then
        _G.SendMailSubjectEditBox:SetText(letter.subject or "sfui: alts mail")
    end
    if _G.SendMailBodyEditBox then
        _G.SendMailBodyEditBox:SetText("")
    end

    -- Begin attaching items sequentially
    SetStepTimer(0.06, function()
        AttachItemStep(letter, 1, 0)
    end)
end

--- Process the next letter in the queue
function SendNextLetter()
    if not _isDispatching then return end

    if #_dispatchQueue == 0 then
        _isDispatching = false
        _waitingForSuccess = false
        if common and common.print then
            common.print(string.format("|cff00ff00alts mail dispatch complete: sent %d letter(s).|r", _totalLetters))
        end
        if _completeCallback then
            _completeCallback(true, "completed")
            _completeCallback = nil
        end
        _progressCallback = nil
        return
    end

    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        mail.CancelDispatch("mailbox closed")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        mail.CancelDispatch("combat entered")
        return
    end

    EnsureSendMailTab()

    local letter = _dispatchQueue[1]
    _currentLetterIndex = _totalLetters - #_dispatchQueue + 1

    if _progressCallback then
        _progressCallback(_currentLetterIndex, _totalLetters, letter.recipient)
    end

    PrepareLetterForAttachment(letter, 0)
end

--- Count total free inventory slots across bags 0 through 4
--- @return number freeSlots
local function GetTotalFreeBagSlots()
    if C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots then
        return C_Container.CalculateTotalNumberOfFreeBagSlots()
    end
    local free = 0
    for bag = 0, mail.GetLastBagIndex() do
        if C_Container and C_Container.GetContainerNumFreeSlots then
            free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
        end
    end
    return free
end

--- Start mailing pending items in manifest
--- @param onProgress function? (currentLetter, totalLetters, recipientName)
--- @param onComplete function? (success, reason)
--- @param targetGUID string? Optional alt GUID to restrict dispatch to
--- @return boolean started, string|nil errorReason
function mail.StartDispatch(onProgress, onComplete, targetGUID)
    if _isDispatching then
        return false, "already dispatching"
    end

    if _isCollectingInbox then
        return false, "inbox collection is active"
    end

    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        return false, "mailbox is not open"
    end

    if InCombatLockdown and InCombatLockdown() then
        return false, "cannot mail in combat"
    end

    local manifest, totalItems, recipientCount = mail.ScanPendingMail(targetGUID)
    if totalItems == 0 or recipientCount == 0 then
        return false, "no pending items to send"
    end

    -- Construct letters queue (max ATTACHMENTS_MAX_SEND items per letter)
    _dispatchQueue = {}
    local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    local myNormRealm = myRealm:gsub("%s+", ""):lower()

    for _, data in pairs(manifest) do
        local recipient = (sfui.alts and sfui.alts.GetMailRecipient and sfui.alts.GetMailRecipient(data))
        if not recipient or recipient == "" then
            recipient = data.name or ""
            if data.surname and data.surname ~= "" and not recipient:find(" ") then
                recipient = string.format("%s %s", recipient, data.surname)
            end
            local targetRealm = (data.realm or ""):gsub("%s+", "")
            if targetRealm ~= "" and targetRealm:lower() ~= myNormRealm then
                recipient = string.format("%s-%s", recipient, targetRealm)
            end
        end

        local currentBatch = {}
        for _, it in ipairs(data.items) do
            table.insert(currentBatch, it)
            if #currentBatch == ATTACHMENTS_MAX_SEND then
                local subj = (it.reason == "disenchant_boe" and "sfui: boe gear") or "sfui: alts mail"
                table.insert(_dispatchQueue, {
                    recipient = recipient,
                    subject   = subj,
                    items     = currentBatch,
                })
                currentBatch = {}
            end
        end

        if #currentBatch > 0 then
            local subj = (currentBatch[1].reason == "disenchant_boe" and "sfui: boe gear") or "sfui: alts mail"
            table.insert(_dispatchQueue, {
                recipient = recipient,
                subject   = subj,
                items     = currentBatch,
            })
        end
    end

    if #_dispatchQueue == 0 then
        return false, "queue construction yielded 0 letters"
    end

    _isDispatching = true
    _waitingForSuccess = false
    _currentLetterIndex = 0
    _totalLetters = #_dispatchQueue
    _progressCallback = onProgress
    _completeCallback = onComplete

    if common and common.print then
        local targetName = targetGUID and manifest[targetGUID] and manifest[targetGUID].name
        if targetName then
            common.print(string.format("|cff00ff00starting alts mail dispatch to %s: %d item(s) in %d letter(s)...|r", targetName, totalItems, _totalLetters))
        else
            common.print(string.format("|cff00ff00starting alts mail dispatch: %d item(s) in %d letter(s)...|r", totalItems, _totalLetters))
        end
    end

    SetStepTimer(0.1, SendNextLetter)
    return true
end

-- ══════════════════════════════════════════════════════════════════════════════
--  Inbox Auto-Collection Engine ("Open All")
-- ══════════════════════════════════════════════════════════════════════════════

local function SetInboxStepTimer(delay, callback)
    if _inboxStepTimer then
        if _inboxStepTimer.Cancel then
            _inboxStepTimer:Cancel()
        end
        _inboxStepTimer = nil
    end
    if delay and callback and C_Timer then
        local timerFn = C_Timer.NewTimer or C_Timer.After
        _inboxStepTimer = timerFn(delay, callback)
    end
end

local function SetInboxSafetyTimer(delay, callback)
    if _inboxSafetyTimer then
        if _inboxSafetyTimer.Cancel then
            _inboxSafetyTimer:Cancel()
        end
        _inboxSafetyTimer = nil
    end
    if delay and callback and C_Timer then
        local timerFn = C_Timer.NewTimer or C_Timer.After
        _inboxSafetyTimer = timerFn(delay, callback)
    end
end

local function CancelInboxTimers()
    SetInboxSafetyTimer(nil)
    SetInboxStepTimer(nil)
end

--- Check if the mail engine is actively collecting inbox mail
--- @return boolean isCollecting
function mail.IsCollectingInbox()
    return _isCollectingInbox
end

--- Get current inbox collection progress
--- @return boolean isCollecting, number current, number total
function mail.GetInboxCollectionProgress()
    if not _isCollectingInbox then
        return false, 0, 0
    end
    return true, _inboxMailIndex, _inboxTotalMail
end

--- Cancel active inbox collection
--- @param reason string?
function mail.CancelInboxCollection(reason)
    if not _isCollectingInbox then return end
    _isCollectingInbox = false
    _inboxMailIndex = 1
    _inboxAttachIndex = ATTACHMENTS_MAX_RECEIVE
    _inboxTotalMail = 0
    _inboxFailedItems = {}

    CancelInboxTimers()

    if C_Mail and C_Mail.SetOpeningAll then
        C_Mail.SetOpeningAll(false)
    end

    if reason and common and common.print then
        common.print(string.format("|cffff9900inbox collection stopped: %s.|r", reason))
    end

    if _inboxCompleteCallback then
        _inboxCompleteCallback(false, reason or "cancelled")
        _inboxCompleteCallback = nil
    end
    _inboxProgressCallback = nil
end

local AdvanceAndProcessNextInboxItem

local function ShouldSkipInboxMail(mailIndex)
    if not GetInboxHeaderInfo then return true end
    local _, _, _, _, _, cod, _, _, _, _, _, _, isGM = GetInboxHeaderInfo(mailIndex)
    if isGM then return true end
    if cod and cod > 0 then return true end
    return false
end

local function HasMailMoney(mailIndex)
    if C_Mail and C_Mail.HasInboxMoney then
        return C_Mail.HasInboxMoney(mailIndex)
    end
    if GetInboxHeaderInfo then
        local _, _, _, _, money = GetInboxHeaderInfo(mailIndex)
        return money and money > 0
    end
    return false
end

local function ProcessCurrentInboxAction()
    if not _isCollectingInbox then return end

    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        mail.CancelInboxCollection("mailbox closed")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        mail.CancelInboxCollection("combat entered")
        return
    end

    if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
        SetInboxStepTimer(0.1, ProcessCurrentInboxAction)
        return
    end

    if GetTotalFreeBagSlots() == 0 then
        mail.CancelInboxCollection("bags are full")
        return
    end

    local totalItems = GetInboxNumItems and GetInboxNumItems() or 0
    if _inboxMailIndex > totalItems then
        _isCollectingInbox = false
        CancelInboxTimers()
        if C_Mail and C_Mail.SetOpeningAll then
            C_Mail.SetOpeningAll(false)
        end
        if common and common.print then
            common.print(string.format("|cff00ff00inbox collection complete: processed %d mail(s).|r", _inboxTotalMail))
        end
        if _inboxCompleteCallback then
            _inboxCompleteCallback(true, "completed")
            _inboxCompleteCallback = nil
        end
        _inboxProgressCallback = nil
        return
    end

    if _inboxProgressCallback then
        _inboxProgressCallback(_inboxMailIndex, _inboxTotalMail)
    end

    if ShouldSkipInboxMail(_inboxMailIndex) then
        _inboxMailIndex = _inboxMailIndex + 1
        _inboxAttachIndex = ATTACHMENTS_MAX_RECEIVE
        SetInboxStepTimer(0.04, AdvanceAndProcessNextInboxItem)
        return
    end

    -- 1. Check money
    if HasMailMoney(_inboxMailIndex) then
        if TakeInboxMoney then
            TakeInboxMoney(_inboxMailIndex)
        end
        SetInboxStepTimer(INBOX_RETRIEVAL_DELAY, AdvanceAndProcessNextInboxItem)
        return
    end

    -- 2. Check attachments
    local foundAttachment = false
    while _inboxAttachIndex >= 1 do
        local hasItem = (HasInboxItem and HasInboxItem(_inboxMailIndex, _inboxAttachIndex))
        if hasItem then
            local itemID = nil
            if GetInboxItem then
                local _, id = GetInboxItem(_inboxMailIndex, _inboxAttachIndex)
                itemID = id
            end
            if not (itemID and _inboxFailedItems[itemID]) then
                foundAttachment = true
                break
            end
        end
        _inboxAttachIndex = _inboxAttachIndex - 1
    end

    if foundAttachment then
        if TakeInboxItem then
            TakeInboxItem(_inboxMailIndex, _inboxAttachIndex)
        end
        _inboxAttachIndex = _inboxAttachIndex - 1
        SetInboxStepTimer(INBOX_RETRIEVAL_DELAY, AdvanceAndProcessNextInboxItem)
        return
    end

    -- Mail has no money or attachments remaining: advance to next mail
    _inboxMailIndex = _inboxMailIndex + 1
    _inboxAttachIndex = ATTACHMENTS_MAX_RECEIVE
    SetInboxStepTimer(0.04, AdvanceAndProcessNextInboxItem)
end

AdvanceAndProcessNextInboxItem = function()
    if not _isCollectingInbox then return end
    SetInboxStepTimer(0.02, ProcessCurrentInboxAction)
end

--- Start automated collection of inbox money and attachments
--- @param onProgress function? (currentMail, totalMail)
--- @param onComplete function? (success, reason)
--- @return boolean started, string|nil errorReason
function mail.StartInboxCollection(onProgress, onComplete)
    if _isCollectingInbox then
        return false, "already collecting inbox"
    end
    if _isDispatching then
        return false, "dispatch is currently active"
    end
    if not _G.MailFrame or not _G.MailFrame:IsShown() then
        return false, "mailbox is not open"
    end
    if InCombatLockdown and InCombatLockdown() then
        return false, "cannot collect mail in combat"
    end

    local numMail = GetInboxNumItems and GetInboxNumItems() or 0
    if numMail == 0 then
        return false, "inbox is empty"
    end

    if GetTotalFreeBagSlots() == 0 then
        return false, "bags are full"
    end

    -- Switch to Inbox tab if needed
    if _G.MailFrameTab1 and _G.MailFrameTab1:IsShown() and not (_G.InboxFrame and _G.InboxFrame:IsShown()) then
        _G.MailFrameTab1:Click()
    elseif _G.MailFrameTab_OnClick and not (_G.InboxFrame and _G.InboxFrame:IsShown()) then
        _G.MailFrameTab_OnClick(nil, 1)
    end

    _isCollectingInbox = true
    _inboxMailIndex = 1
    _inboxAttachIndex = ATTACHMENTS_MAX_RECEIVE
    _inboxTotalMail = numMail
    _inboxFailedItems = {}
    _inboxProgressCallback = onProgress
    _inboxCompleteCallback = onComplete

    if C_Mail and C_Mail.SetOpeningAll then
        C_Mail.SetOpeningAll(true)
    end

    if common and common.print then
        common.print(string.format("|cff00ff00starting inbox collection: %d mail(s)...|r", numMail))
    end

    local function ScheduleInboxSafety()
        SetInboxSafetyTimer(10.0, function()
            if not _isCollectingInbox then return end
            if common and common.print then
                common.print("|cffff9900inbox retrieval timeout, skipping to next mail...|r")
            end
            _inboxMailIndex = _inboxMailIndex + 1
            _inboxAttachIndex = ATTACHMENTS_MAX_RECEIVE
            ScheduleInboxSafety()
            SetInboxStepTimer(0.1, AdvanceAndProcessNextInboxItem)
        end)
    end
    ScheduleInboxSafety()

    SetInboxStepTimer(0.08, AdvanceAndProcessNextInboxItem)
    return true
end

-- ─── Event Registration via SFUI Dispatcher ──────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    --- Common handler for successful letter delivery
    local function HandleMailSuccess()
        if not _isDispatching or not _waitingForSuccess then return end
        _waitingForSuccess = false
        _secureTransferActive = false
        CancelTimers()

        if #_dispatchQueue > 0 then
            local sentLetter = table.remove(_dispatchQueue, 1)
            if sentLetter and common and common.print then
                common.print(string.format("|cff00ff00mailed %d item(s) to %s.|r", #sentLetter.items, sentLetter.recipient))
            end
        end

        if #_dispatchQueue == 0 then
            _isDispatching = false
            if common and common.print then
                common.print(string.format("|cff00ff00alts mail dispatch complete: sent %d letter(s).|r", _totalLetters))
            end
            if _completeCallback then
                _completeCallback(true, "completed")
                _completeCallback = nil
            end
            _progressCallback = nil
        else
            -- Inter-letter cooldown: gives server time to process bag inventory updates
            SetStepTimer(INTER_LETTER_DELAY, SendNextLetter)
        end
    end

    sfui.events.RegisterEvent("MAIL_SEND_SUCCESS", HandleMailSuccess)
    sfui.events.RegisterEvent("MAIL_SUCCESS", HandleMailSuccess)

    sfui.events.RegisterEvent("MAIL_FAILED", function(_, itemID)
        if _isCollectingInbox and itemID then
            _inboxFailedItems[itemID] = true
        end

        if not _isDispatching then return end
        CancelTimers()
        _waitingForSuccess = false
        _secureTransferActive = false

        local failedTask = _dispatchQueue[1]
        local recipient = (failedTask and failedTask.recipient) or "recipient"

        if failedTask then
            failedTask.sendRetries = (failedTask.sendRetries or 0) + 1
            if failedTask.sendRetries <= 1 then
                if common and common.print then
                    common.print(string.format("|cffff9900mail send failed for %s (server busy), retrying in 1.2s...|r", recipient))
                end
                if ClearSendMail then ClearSendMail() end
                SetStepTimer(1.2, SendNextLetter)
                return
            end
        end

        -- Second failure: skip this recipient and continue remaining queue
        if common and common.print then
            common.print(string.format("|cffff3333failed sending mail to %s (skipped to next recipient).|r", recipient))
        end
        table.remove(_dispatchQueue, 1)
        if ClearSendMail then ClearSendMail() end

        if #_dispatchQueue > 0 then
            SetStepTimer(INTER_LETTER_DELAY, SendNextLetter)
        else
            _isDispatching = false
            if _completeCallback then
                _completeCallback(false, "one or more letters failed")
                _completeCallback = nil
            end
            _progressCallback = nil
        end
    end)

    sfui.events.RegisterEvent("MAIL_INBOX_UPDATE", function()
        if _isCollectingInbox then
            local curNum = (GetInboxNumItems and GetInboxNumItems()) or 0
            if curNum ~= _inboxTotalMail then
                _inboxMailIndex = 1
                _inboxAttachIndex = ATTACHMENTS_MAX_RECEIVE
            end
        end
    end)

    sfui.events.RegisterEvent("MAIL_CLOSED", function()
        mail.CancelDispatch("mailbox closed")
        mail.CancelInboxCollection("mailbox closed")
    end)

    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        mail.CancelDispatch("combat entered")
        mail.CancelInboxCollection("combat entered")
    end)

    sfui.events.RegisterEvent("SECURE_TRANSFER_CONFIRM_SEND_MAIL", function()
        _secureTransferActive = true
        if _isDispatching and common and common.print then
            local curr = _dispatchQueue[1]
            local target = (curr and curr.recipient) or "recipient"
            common.print(string.format("|cffffff00awaiting confirmation popup for %s...|r", target))
        end
    end)

    sfui.events.RegisterEvent("SECURE_TRANSFER_CANCEL", function()
        local wasActive = _secureTransferActive
        _secureTransferActive = false
        if _isDispatching and _waitingForSuccess and wasActive then
            CancelTimers()
            local cancelledTask = _dispatchQueue[1]
            local rec = (cancelledTask and cancelledTask.recipient) or "recipient"
            if common and common.print then
                common.print(string.format("|cffff9900mail confirmation cancelled for %s.|r", rec))
            end
            _waitingForSuccess = false
            table.remove(_dispatchQueue, 1)
            if ClearSendMail then ClearSendMail() end
            if #_dispatchQueue > 0 then
                SetStepTimer(INTER_LETTER_DELAY, SendNextLetter)
            else
                _isDispatching = false
                if _completeCallback then
                    _completeCallback(false, "transfer cancelled")
                    _completeCallback = nil
                end
                _progressCallback = nil
            end
        end
    end)
end

