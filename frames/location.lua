local addonName, addon = ...
sfui                   = sfui or {}
sfui.location          = {}
local sfui_common      = sfui.common
local sfui_config      = sfui.config
local sfui_events      = sfui.events

sfui_config.location   = sfui_config.location or {
    fillSound     = 10157,
    printOnInvite = true,
}

-- -------------------------------------------------------
-- Module state
-- -------------------------------------------------------
-- Module state
-- -------------------------------------------------------
local pendingDungeon    = nil
local pendingLeader     = nil
local pendingInstanceID = nil
local pendingBaseName   = nil
local pendingRole       = nil
local watchingRoster    = false

local function is_enabled()
    local reminder = (SfuiDB and SfuiDB.keystoneReminder ~= false)
    local popup    = (SfuiDB and SfuiDB.autoDungeonPortalPopup ~= false)
    return reminder or popup
end

local function reset_state(hidePopup)
    pendingDungeon    = nil
    pendingLeader     = nil
    pendingInstanceID = nil
    pendingBaseName   = nil
    pendingRole       = nil
    if watchingRoster then
        sfui_events.UnregisterEvent("GROUP_ROSTER_UPDATE", sfui.location.on_roster_update)
        watchingRoster = false
    end
    if hidePopup and sfui.portals and sfui.portals.HideGroupPortalPopup then
        sfui.portals.HideGroupPortalPopup()
    end
end

local cyan    = sfui_config.colors.cyan
local purple  = sfui_config.colors.purple
local cc      = string.format("|cff%02x%02x%02x", cyan[1] * 255, cyan[2] * 255, cyan[3] * 255)
local pc      = string.format("|cff%02x%02x%02x", purple[1] * 255, purple[2] * 255, purple[3] * 255)
local reset_c = "|r"

-- -------------------------------------------------------
-- Core: group-filled handler
-- -------------------------------------------------------
function sfui.location.on_roster_update()
    if GetNumGroupMembers() >= 5 then
        if (SfuiDB and SfuiDB.keystoneReminder ~= false) then
            if sfui_config.location.fillSound > 0 then
                PlaySound(sfui_config.location.fillSound, "Dialog")
            end

            sfui_common.print(
                pc .. "{rt3} GROUP FILLED" .. reset_c
                .. " -> " .. cc .. (pendingDungeon or "unknown dungeon") .. reset_c
                .. " | leader: " .. tostring(pendingLeader)
            )
        end

        local showPopup = (SfuiDB and SfuiDB.autoDungeonPortalPopup ~= false)
        if showPopup and sfui.portals and sfui.portals.ShowGroupPortalPopup then
            local instID = pendingInstanceID or pendingBaseName or pendingDungeon
            local dName  = pendingBaseName or pendingDungeon
            sfui.portals.ShowGroupPortalPopup(instID, dName, pendingRole, true)
        end

        reset_state(false)
    end
end

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
    if actInfo.categoryID == 2 then
        return true
    end
    return false
end

local function on_application_status(event, searchResultID, newStatus)
    if not is_enabled() then return end
    if newStatus ~= "invited" and newStatus ~= "inviteaccepted" then return end

    local resultData = C_LFGList.GetSearchResultInfo(searchResultID)
    if not resultData then return end

    local activityID = get_activity_id(resultData)
    if not activityID then
        if newStatus == "inviteaccepted" then reset_state(true) end
        return
    end

    local activityInfo = C_LFGList.GetActivityInfoTable(activityID, nil, resultData.isWarMode)
    if not is_valid_dungeon_activity(activityInfo) then
        if newStatus == "inviteaccepted" then reset_state(true) end
        return
    end

    local dungeonName = activityInfo.fullName or "?"
    local keyLevel    = resultData.name or ""
    local leader      = resultData.leaderName or ""
    local pendingDgn  = dungeonName .. " " .. tostring(keyLevel)

    -- Handle initial invite pop-up
    if newStatus == "invited" then
        if (SfuiDB and SfuiDB.keystoneReminder ~= false) then
            sfui_common.print(
                pc .. "Keystone invite received" .. reset_c
                .. " -> " .. cc .. pendingDgn .. reset_c
                .. " | leader: " .. tostring(leader)
            )
        end
        return
    end

    -- Fall-through: newStatus == "inviteaccepted"
    pendingDungeon    = pendingDgn
    pendingLeader     = leader
    pendingInstanceID = activityInfo.mapID
    pendingBaseName   = dungeonName
    local appliedRole = nil
    if C_LFGList.GetApplicationInfo then
        local _, _, _, _, role = C_LFGList.GetApplicationInfo(searchResultID)
        appliedRole = role
    end
    pendingRole       = appliedRole

    if sfui_config.location.printOnInvite and (SfuiDB and SfuiDB.keystoneReminder ~= false) then
        sfui_common.print(
            pc .. "Keystone accepted" .. reset_c
            .. " -> " .. cc .. pendingDungeon .. reset_c
            .. " | leader: " .. tostring(pendingLeader)
            .. " (waiting for group to fill...)"
        )
    end

    -- If user opted into showing portal popup on join (onlyWhenFull == false)
    local popupEnabled = (SfuiDB and SfuiDB.autoDungeonPortalPopup ~= false)
    local onlyWhenFull = (SfuiDB and SfuiDB.portalPopupOnlyWhenFull ~= nil and SfuiDB.portalPopupOnlyWhenFull)
        or (SfuiDB and SfuiDB.portalPopupOnlyWhenFull == nil and true)
    if popupEnabled and not onlyWhenFull and sfui.portals and sfui.portals.ShowGroupPortalPopup then
        sfui.portals.ShowGroupPortalPopup(pendingInstanceID or pendingBaseName, pendingBaseName, pendingRole, false)
    end

    -- Register roster watcher only now (transient; unregistered on fill or reset)
    if not watchingRoster then
        sfui_events.RegisterEvent("GROUP_ROSTER_UPDATE", sfui.location.on_roster_update)
        watchingRoster = true
    end

    -- Immediate check in case we're the last to accept
    sfui.location.on_roster_update()
end

-- -------------------------------------------------------
-- Cleanup: leaving a party mid-queue cancels the reminder
-- -------------------------------------------------------
local function on_party_leave()
    reset_state(true)
end

local function on_active_entry_update()
    if not is_enabled() then return end

    local hasActive = C_LFGList.HasActiveEntryInfo()
    if not hasActive then
        -- NOTE: Do NOT reset_state here!
        -- When the group reaches 5/5, Blizzard automatically delists the entry from LFG.
        -- We preserve pending data so sfui.location.on_roster_update can announce GROUP FILLED.
        return
    end

    local entryInfo = C_LFGList.GetActiveEntryInfo()
    if not entryInfo then return end

    local activityID = get_activity_id(entryInfo)
    if not activityID then return end

    local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
    if not is_valid_dungeon_activity(activityInfo) then return end

    local dungeonName = activityInfo.fullName or "?"
    local keyLevel    = entryInfo.name or ""
    local leader      = UnitName("player")
    local pendingDgn  = dungeonName .. " " .. tostring(keyLevel)

    pendingDungeon    = pendingDgn
    pendingLeader     = leader
    pendingInstanceID = activityInfo.mapID
    pendingBaseName   = dungeonName
    pendingRole       = UnitGroupRolesAssigned("player")

    if not watchingRoster then
        sfui_events.RegisterEvent("GROUP_ROSTER_UPDATE", sfui.location.on_roster_update)
        watchingRoster = true
        
        if sfui_config.location.printOnInvite and (SfuiDB and SfuiDB.keystoneReminder ~= false) then
            sfui_common.print(
                pc .. "Keystone group listed" .. reset_c
                .. " -> " .. cc .. pendingDungeon .. reset_c
                .. " (waiting for group to fill...)"
            )
        end
    end
end

-- -------------------------------------------------------
-- Instance & Difficulty Status Badge
-- -------------------------------------------------------
local lastInstancePrint = nil

local function print_instance_status()
    if not is_enabled() then return end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType == "none" then
        lastInstancePrint = nil
        return
    end

    local name, _, difficultyID, difficultyName = GetInstanceInfo()
    if not name or name == "" then return end

    local now = GetTime()
    if lastInstancePrint and (now - lastInstancePrint < 3) then return end
    lastInstancePrint = now

    local diffText = difficultyName or "Normal"
    local activeKey = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()
    if activeKey and activeKey > 0 then
        diffText = "Mythic +" .. tostring(activeKey)
    end

    local specID, isDefault = sfui.common.get_effective_loot_spec_id()
    local specName = "Current Spec"
    local specColor = cc

    if specID and specID ~= 0 then
        local sName = sfui.common.get_spec_name(specID)
        if sName then
            specName = isDefault and (sName .. " (Default)") or sName
        end
        local r, g, b = sfui.common.get_spec_color(specID)
        specColor = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    end

    sfui_common.print(
        pc .. name .. reset_c
        .. " (" .. cc .. diffText .. reset_c .. ")"
        .. " · loot spec: " .. specColor .. specName .. reset_c
    )
end

function sfui.location.PrintInstanceStatus()
    print_instance_status()
end

-- -------------------------------------------------------
-- Event wiring via sfui.events (shared multiplexer)
-- -------------------------------------------------------
sfui_events.RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED", on_application_status)
sfui_events.RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", on_active_entry_update)
sfui_events.RegisterEvent("GROUP_LEFT", on_party_leave)
sfui_events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(0.5, print_instance_status)
    C_Timer.After(0.5, on_active_entry_update)
end)
sfui_events.RegisterEvent("ZONE_CHANGED_NEW_AREA", print_instance_status)
sfui_events.RegisterEvent("CHALLENGE_MODE_START", function()
    lastInstancePrint = nil
    C_Timer.After(0.2, print_instance_status)
end)

local _locDebug = {}
function sfui.location_debug_info()
    _locDebug.watchingRoster = watchingRoster
    _locDebug.pendingDungeon = pendingDungeon ~= nil
    _locDebug.enabled = is_enabled()
    return _locDebug
end
