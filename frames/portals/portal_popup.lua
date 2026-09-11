local addonName, addon = ...
sfui                   = sfui or {}
sfui.portals           = sfui.portals or {}
sfui.portals.popup     = {}
local sfui_common      = sfui.common
local sfui_config      = sfui.config
local sfui_events      = sfui.events

-- ─── Constants & Configuration ───────────────────────────────────────────────
local math_floor       = math.floor
local CreateFrame      = _G.CreateFrame
local UIParent         = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local PlaySound        = _G.PlaySound
local GameTooltip      = sfui.tooltip or _G.GameTooltip
local C_Spell          = _G.C_Spell
local C_Timer          = _G.C_Timer
local C_LFGList        = _G.C_LFGList
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local GetNumGroupMembers = _G.GetNumGroupMembers
local IsInInstance     = _G.IsInInstance
local IsInRaid         = _G.IsInRaid

local FRAME_W = 270
local FRAME_H = 74

local ROLE_INFO = {
    TANK    = { atlas = "GM-icon-role-tank",   text = "Tank",   color = { 0.4, 0.7, 1.0 } },
    HEALER  = { atlas = "GM-icon-role-healer", text = "Healer", color = { 0.3, 1.0, 0.4 } },
    DAMAGER = { atlas = "GM-icon-role-dps",    text = "DPS",    color = { 1.0, 0.4, 0.4 } },
}

-- ─── State ───────────────────────────────────────────────────────────────────
local popupFrame   = nil
local dismissTimer = nil
local pendingPopup = nil

local function is_enabled()
    return SfuiDB and SfuiDB.autoDungeonPortalPopup ~= false
end

-- ─── UI Creation ─────────────────────────────────────────────────────────────
local function get_or_create_popup()
    if popupFrame then return popupFrame end

    local f = CreateFrame("Frame", "SfuiDungeonPortalPopup", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Backdrop: clean minimal dark aesthetic with pixel scale border
    local pScale = sfui.pixelScale or 1
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = pScale,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
    local gray = (sfui_config and sfui_config.colors and sfui_config.colors.gray) or { 0.2, 0.2, 0.2, 1 }
    f:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)

    -- Draggable placement
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            SfuiDB.portalPopupX = math_floor(cx - ux)
            SfuiDB.portalPopupY = math_floor(cy - uy)
        end
    end)

    -- Close Button
    local closeBtn = sfui_common.create_close_button(f, function()
        f:Hide()
    end, 18)
    closeBtn:ClearAllPoints()
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- Header Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetText("|cff00ffffGroup is full!|r")
    f.title = title

    -- Teleport Action Card (InsecureActionButtonTemplate for taint-free spell casting)
    local card = CreateFrame("Button", "SfuiDungeonPortalPopupCard", f, "InsecureActionButtonTemplate,BackdropTemplate")
    card:SetSize(FRAME_W - 14, 42)
    card:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 7, 7)
    card:RegisterForClicks("AnyUp", "AnyDown")
    card:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = pScale,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    card:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

    card:HookScript("OnEnter", function(self)
        card:SetBackdropBorderColor(0.0, 1.0, 1.0, 0.9)
        if self.spellID and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetSpellByID(self.spellID)
            if not self.isKnown then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffff2020[Portal not in spellbook]|r", 1, 0.2, 0.2)
            end
            GameTooltip:Show()
        end
    end)

    card:HookScript("OnLeave", function()
        card:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
        if GameTooltip then GameTooltip:Hide() end
    end)

    card:HookScript("OnClick", function(self)
        if not self.isKnown then
            if sfui_common and sfui_common.print then
                sfui_common.print("|cffff5555[SFUI] You have not learned the teleport for this dungeon.|r")
            end
        end
        if not InCombatLockdown() then
            f:Hide()
        end
    end)

    -- Portal Spell Icon
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", card, "LEFT", 5, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card.icon = icon

    -- Cooldown Sweep
    local cd = CreateFrame("Cooldown", "$parentCooldown", card, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    card.cooldown = cd

    -- Unlearned Warning Icon
    local warn = card:CreateTexture(nil, "OVERLAY")
    warn:SetSize(14, 14)
    warn:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    warn:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    warn:Hide()
    card.warn = warn

    -- Dungeon Name Text
    local dName = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    dName:SetPoint("RIGHT", card, "RIGHT", -6, 0)
    dName:SetJustifyH("LEFT")
    dName:SetWordWrap(false)
    card.dungeonName = dName

    -- Role Icon & Role Text
    local roleIcon = card:CreateTexture(nil, "OVERLAY")
    roleIcon:SetSize(14, 14)
    roleIcon:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
    card.roleIcon = roleIcon

    local roleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleText:SetPoint("LEFT", roleIcon, "RIGHT", 4, 0)
    roleText:SetJustifyH("LEFT")
    card.roleText = roleText

    f.card = card

    -- Restore saved position
    local defPos = (sfui_config and sfui_config.portalPopup and sfui_config.portalPopup.defaultPosition) or { x = 0, y = 180 }
    local x = (SfuiDB and SfuiDB.portalPopupX) or defPos.x
    local y = (SfuiDB and SfuiDB.portalPopupY) or defPos.y
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)

    popupFrame = f
    return f
end

-- ─── Public API ─────────────────────────────────────────────────────────────

--- Shows the dungeon portal popup with a one-click teleport button.
--- @param instanceIdentifier number|string Instance ID or dungeon name
--- @param dungeonName        string        Optional display name
--- @param role               string        Optional assigned role ("TANK", "HEALER", "DAMAGER")
--- @param isFull             boolean       True if group filled to 5/5, false if joined
--- Shows the dungeon portal popup with a one-click teleport button.
--- @param instanceIdentifier number|string Instance ID or dungeon name
--- @param dungeonName        string        Optional display name
--- @param role               string        Optional assigned role ("TANK", "HEALER", "DAMAGER")
--- @param isFull             boolean       True if group filled to 5/5, false if joined
function sfui.portals.ShowGroupPortalPopup(instanceIdentifier, dungeonName, role, isFull)
    if not is_enabled() then return end

    if InCombatLockdown() then
        pendingPopup = {
            id     = instanceIdentifier,
            name   = dungeonName,
            role   = role,
            isFull = isFull,
        }
        sfui_events.RegisterEvent("PLAYER_REGEN_ENABLED", sfui.portals.popup.OnRegenEnabled)
        return
    end

    -- Idempotency check: don't re-trigger or play sound twice if already showing for the exact same instance/state
    if popupFrame and popupFrame:IsShown() and popupFrame._sfui_last_inst == instanceIdentifier and popupFrame._sfui_last_full == isFull then
        return
    end

    local popup = get_or_create_popup()
    local card  = popup.card

    -- Resolve portal spell from SFUI portals database
    local spellID, resolvedName, isKnown = sfui.portals.GetDungeonPortal(instanceIdentifier)
    if not spellID and dungeonName then
        spellID, resolvedName, isKnown = sfui.portals.GetDungeonPortal(dungeonName)
    end

    local displayName = resolvedName or dungeonName or "Dungeon"
    card.spellID = spellID
    card.isKnown = isKnown

    -- Update title
    if isFull then
        popup.title:SetText("|cff00ffffGroup is full!|r")
    else
        popup.title:SetText("|cff00ff00Mythic+ group joined!|r")
    end

    card.dungeonName:SetText(displayName)

    -- Update Spell Attribute & Icon
    if spellID and isKnown then
        card:SetAttribute("type", "spell")
        card:SetAttribute("spell", spellID)

        local iconID = (sfui_common and sfui_common.get_spell_icon(spellID)) or sfui.common.get_spell_icon(spellID) or 134400
        card.icon:SetTexture(iconID)
        card.icon:SetDesaturated(false)
        card.warn:Hide()

        local startTime, duration, _, modRate = (sfui_common or sfui.common).get_spell_cooldown(spellID)
        if startTime > 0 and duration > 0 then
            card.cooldown:SetCooldown(startTime, duration, modRate or 1)
            card.cooldown:Show()
        else
            card.cooldown:Hide()
        end
    else
        card:SetAttribute("type", nil)
        card:SetAttribute("spell", nil)

        local iconID = 134400
        if spellID then
            iconID = (sfui_common or sfui.common).get_spell_icon(spellID) or 134400
        end
        card.icon:SetTexture(iconID)
        card.icon:SetDesaturated(true)
        card.warn:Show()
        card.cooldown:Hide()
    end

    -- Update Role indicator
    local playerRole = role
    if not playerRole or playerRole == "NONE" then
        playerRole = UnitGroupRolesAssigned("player")
    end
    if not playerRole or playerRole == "NONE" then
        playerRole = sfui.common.get_spec_role()
    end

    local rInfo = playerRole and ROLE_INFO[playerRole]
    if rInfo then
        card.roleIcon:SetAtlas(rInfo.atlas)
        card.roleIcon:Show()
        card.roleText:SetText(rInfo.text)
        card.roleText:SetTextColor(rInfo.color[1], rInfo.color[2], rInfo.color[3], 1)
        card.roleText:Show()
    else
        card.roleIcon:Hide()
        card.roleText:Hide()
    end

    popup._sfui_last_inst = instanceIdentifier
    popup._sfui_last_full = isFull

    -- Play notification sound
    PlaySound(844, "Dialog") -- SOUNDKIT.IG_QUEST_LOG_OPEN

    popup:Show()

    -- Auto-dismiss timer
    if dismissTimer then
        dismissTimer:Cancel()
        dismissTimer = nil
    end
    local autoHide = (sfui_config and sfui_config.portalPopup and sfui_config.portalPopup.autoHideSecs) or 45
    dismissTimer = C_Timer.NewTimer(autoHide, function()
        dismissTimer = nil
        if popup:IsShown() and not InCombatLockdown() then
            popup:Hide()
        end
    end)
end

--- Hides the portal popup if currently shown.
function sfui.portals.HideGroupPortalPopup()
    pendingPopup = nil
    if dismissTimer then
        dismissTimer:Cancel()
        dismissTimer = nil
    end
    if popupFrame then
        popupFrame._sfui_last_inst = nil
        popupFrame._sfui_last_full = nil
        if popupFrame:IsShown() and not InCombatLockdown() then
            popupFrame:Hide()
        end
    end
end

--- Preview the popup dialog using the first active season portal.
function sfui.portals.TestPortalPopup()
    if popupFrame then
        popupFrame._sfui_last_inst = nil
        popupFrame._sfui_last_full = nil
    end
    local db = sfui.portals_db
    local testPortal = db and db.SEASON_PORTALS and db.SEASON_PORTALS[1]
    if testPortal then
        sfui.portals.ShowGroupPortalPopup(testPortal.instance, testPortal.name, UnitGroupRolesAssigned("player"), true)
        if sfui_common and sfui_common.print then
            sfui_common.print("|cff00ffff[SFUI] Previewing dungeon portal popup for " .. testPortal.name .. ".|r")
        end
    else
        sfui.portals.ShowGroupPortalPopup(1762, "Kings' Rest", UnitGroupRolesAssigned("player"), true)
    end
end

-- ─── LFG & Group Complete Detection State Machine ─────────────────────────
local currentGroup = nil

local function get_activity_id(data)
    if not data then return nil end
    if type(data.activityID) == "number" and data.activityID > 0 then
        return data.activityID
    end
    if type(data.activityIDs) == "table" and data.activityIDs[1] then
        return data.activityIDs[1]
    end
    return nil
end

local function is_valid_dungeon_activity(actInfo)
    if not actInfo then return false end
    if actInfo.isMythicPlusActivity or actInfo.isMythicActivity then
        return true
    end
    if actInfo.categoryID == 2 then -- Dungeons category
        return true
    end
    return false
end

local function check_group_full()
    if not is_enabled() then return end
    if not currentGroup or currentGroup.notifiedFull then return end
    if IsInRaid and IsInRaid() then return end

    local count = GetNumGroupMembers()
    if count >= 5 then
        currentGroup.notifiedFull = true
        local role = currentGroup.appliedRole
        if not role or role == "NONE" then
            role = UnitGroupRolesAssigned("player")
        end
        sfui.portals.ShowGroupPortalPopup(currentGroup.instanceId, currentGroup.activityName, role, true)
    end
end

local function check_active_entry()
    if not is_enabled() then return end
    if currentGroup and currentGroup.notifiedFull then return end

    local hasActive = C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()
    if not hasActive then
        -- NOTE: Do NOT nil currentGroup here!
        -- When the 5th member joins, Blizzard automatically delists the group from LFG.
        -- We preserve currentGroup so check_group_full() can fire from GROUP_ROSTER_UPDATE.
        return
    end

    local entryData = C_LFGList.GetActiveEntryInfo()
    if not entryData then return end

    local actID = get_activity_id(entryData)
    local actInfo = actID and C_LFGList.GetActivityInfoTable(actID)
    if not is_valid_dungeon_activity(actInfo) then return end

    if not currentGroup or currentGroup.instanceId ~= actInfo.mapID then
        currentGroup = {
            instanceId   = actInfo.mapID,
            activityName = actInfo.fullName,
            appliedRole  = UnitGroupRolesAssigned("player"),
            notifiedFull = false,
            notifiedJoin = false,
        }
    end

    check_group_full()
end

local function on_application_status(event, searchResultID, newStatus)
    if not is_enabled() then return end
    if newStatus ~= "inviteaccepted" then return end

    local searchResultInfo = C_LFGList and C_LFGList.GetSearchResultInfo and C_LFGList.GetSearchResultInfo(searchResultID)
    if not searchResultInfo then return end

    local actID = get_activity_id(searchResultInfo)
    local actInfo = actID and C_LFGList.GetActivityInfoTable(actID, nil, searchResultInfo.isWarMode)
    if not is_valid_dungeon_activity(actInfo) then return end

    local appliedRole = nil
    if C_LFGList.GetApplicationInfo then
        local _, _, _, _, role = C_LFGList.GetApplicationInfo(searchResultID)
        appliedRole = role
    end

    currentGroup = {
        instanceId   = actInfo.mapID,
        activityName = actInfo.fullName,
        appliedRole  = appliedRole,
        notifiedFull = false,
        notifiedJoin = false,
    }

    local onlyWhenFull = (SfuiDB and SfuiDB.portalPopupOnlyWhenFull ~= nil and SfuiDB.portalPopupOnlyWhenFull)
        or (sfui_config and sfui_config.portalPopup and sfui_config.portalPopup.onlyWhenFull)
        or false

    if not onlyWhenFull and not currentGroup.notifiedJoin then
        currentGroup.notifiedJoin = true
        sfui.portals.ShowGroupPortalPopup(actInfo.mapID, actInfo.fullName, appliedRole, false)
    end

    check_group_full()
end

-- ─── Event Handlers ──────────────────────────────────────────────────────────
function sfui.portals.popup.OnRegenEnabled()
    sfui_events.UnregisterEvent("PLAYER_REGEN_ENABLED", sfui.portals.popup.OnRegenEnabled)
    if pendingPopup then
        local p = pendingPopup
        pendingPopup = nil
        sfui.portals.ShowGroupPortalPopup(p.id, p.name, p.role, p.isFull)
    end
end

sfui_events.RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", check_active_entry)
sfui_events.RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED", on_application_status)
sfui_events.RegisterEvent("GROUP_ROSTER_UPDATE", check_group_full)

sfui_events.RegisterEvent("GROUP_LEFT", function()
    currentGroup = nil
    sfui.portals.HideGroupPortalPopup()
end)

sfui_events.RegisterEvent("CHALLENGE_MODE_START", function()
    currentGroup = nil
    sfui.portals.HideGroupPortalPopup()
end)

sfui_events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        currentGroup = nil
        sfui.portals.HideGroupPortalPopup()
    else
        sfui.portals.HideGroupPortalPopup()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, check_active_entry)
        end
    end
end)

sfui_events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if popupFrame and popupFrame:IsShown() and not InCombatLockdown() then
        popupFrame:Hide()
    end
end)

function sfui.portals.popup_debug()
    print("|cff00ffff[SFUI Portal Popup Debug]|r")
    print("  enabled:", is_enabled())
    print("  onlyWhenFull:", (SfuiDB and SfuiDB.portalPopupOnlyWhenFull))
    print("  numGroupMembers:", GetNumGroupMembers())
    print("  hasActiveEntry:", C_LFGList and C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo())
    if currentGroup then
        print("  currentGroup.instanceId:", currentGroup.instanceId)
        print("  currentGroup.activityName:", currentGroup.activityName)
        print("  currentGroup.appliedRole:", currentGroup.appliedRole)
        print("  currentGroup.notifiedFull:", currentGroup.notifiedFull)
    else
        print("  currentGroup: nil")
    end
end

-- Backward compatibility & automation aliases
sfui.automation = sfui.automation or {}
sfui.automation.ShowGroupPortalPopup = sfui.portals.ShowGroupPortalPopup
sfui.automation.HideGroupPortalPopup = sfui.portals.HideGroupPortalPopup
sfui.automation.TestPortalPopup      = sfui.portals.TestPortalPopup

