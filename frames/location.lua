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
local pendingDungeon = nil
local pendingLeader  = nil
local watchingRoster = false

local function is_enabled()
    return SfuiDB and SfuiDB.keystoneReminder ~= false
end

local function reset_state()
    pendingDungeon = nil
    pendingLeader  = nil
    if watchingRoster then
        sfui_events.UnregisterEvent("GROUP_ROSTER_UPDATE", sfui.location.on_roster_update)
        watchingRoster = false
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

        reset_state()
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

local function parse_keystone_level(str)
    if sfui_common and sfui_common.parse_keystone_level then
        return sfui_common.parse_keystone_level(str)
    end
    if not str then return nil end
    if type(str) == "number" then return (str >= 2 and str <= 40) and str or nil end
    if type(str) ~= "string" or str == "" then return nil end
    local plusLevel = str:match("[+]%s*(%d+)")
    if plusLevel then
        local num = tonumber(plusLevel)
        if num and num >= 2 and num <= 40 then return num end
    end
    local tagLevel = str:match("[Kk][Ee][Yy]%s*(%d+)") or str:match("%((%d+)%)")
    if tagLevel then
        local num = tonumber(tagLevel)
        if num and num >= 2 and num <= 40 then return num end
    end
    for numStr in str:gmatch("%f[%d](%d+)%f[%D]") do
        local num = tonumber(numStr)
        if num and num >= 2 and num <= 40 then return num end
    end
    return nil
end

local function get_group_leader_name()
    if UnitIsGroupLeader("player") or not IsInGroup() then
        return UnitName("player")
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitIsGroupLeader(unit) then
                local name = UnitName(unit)
                if name and name ~= "" then return name end
            end
        end
    else
        local num = GetNumGroupMembers()
        for i = 1, (num > 0 and num - 1 or 4) do
            local unit = "party" .. i
            if UnitIsGroupLeader(unit) then
                local name = UnitName(unit)
                if name and name ~= "" then return name end
            end
        end
    end
    return pendingLeader or "leader"
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
        if newStatus == "inviteaccepted" then reset_state() end
        return
    end

    local dungeonName = activityInfo.shortName or activityInfo.fullName or "?"
    local title       = resultData.name or ""
    local keyLevel    = parse_keystone_level(title)

    local pendingDgn  = (keyLevel and keyLevel > 0) and (dungeonName .. " +" .. tostring(keyLevel)) or dungeonName
    if title ~= "" and not title:find(dungeonName, 1, true) and not title:match("^%s*%+?%s*[0-9]+%s*$") then
        pendingDgn = pendingDgn .. " (" .. title .. ")"
    end

    local leader = resultData.leaderName or ""

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
    pendingDungeon = pendingDgn
    pendingLeader  = leader

    if sfui_config.location.printOnInvite and (SfuiDB and SfuiDB.keystoneReminder ~= false) then
        sfui_common.print(
            pc .. "Keystone accepted" .. reset_c
            .. " -> " .. cc .. pendingDungeon .. reset_c
            .. " | leader: " .. tostring(pendingLeader)
            .. " (waiting for group to fill...)"
        )
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
    reset_state()
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

    local isLeader = UnitIsGroupLeader("player") or not IsInGroup()

    -- 1. Extract keystone level from the active listing title (highest priority)
    local keyLevel = parse_keystone_level(entryInfo.name)

    -- 2. Fallback: ONLY if the local player is the group leader and no level was in the title,
    -- check if the leader has a keystone in their bags for this specific activity.
    -- (Never inspect bags for a non-leader, and never use a keystone from an unrelated dungeon!)
    if not keyLevel and isLeader then
        if C_LFGList and C_LFGList.GetKeystoneForActivity then
            local actKey = C_LFGList.GetKeystoneForActivity(activityID)
            if actKey and actKey > 0 then
                keyLevel = actKey
            end
        end
    end

    -- 3. Fallback: if we already have a pending keystone level from on_application_status, preserve it
    if not keyLevel and pendingDungeon then
        local prevLevel = parse_keystone_level(pendingDungeon)
        if prevLevel then
            keyLevel = prevLevel
        end
    end

    local dungeonName = activityInfo.shortName or activityInfo.fullName or "?"
    local pendingDgn  = (keyLevel and keyLevel > 0) and (dungeonName .. " +" .. tostring(keyLevel)) or dungeonName
    local customTitle = entryInfo.name or ""
    if customTitle ~= "" and not customTitle:find(dungeonName, 1, true) and not customTitle:match("^%s*%+?%s*[0-9]+%s*$") then
        pendingDgn = pendingDgn .. " (" .. customTitle .. ")"
    end

    local leader   = get_group_leader_name()
    pendingDungeon = pendingDgn
    pendingLeader  = leader

    if not watchingRoster then
        sfui_events.RegisterEvent("GROUP_ROSTER_UPDATE", sfui.location.on_roster_update)
        watchingRoster = true
        
        if sfui_config.location.printOnInvite and (SfuiDB and SfuiDB.keystoneReminder ~= false) then
            local leaderSuffix = (not isLeader and pendingLeader) and (" | leader: " .. tostring(pendingLeader)) or ""
            sfui_common.print(
                pc .. "Keystone group listed" .. reset_c
                .. " -> " .. cc .. pendingDungeon .. reset_c
                .. leaderSuffix
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
    elseif C_ChallengeMode and C_ChallengeMode.GetSlottedKeystoneInfo then
        local _, _, slottedLevel = C_ChallengeMode.GetSlottedKeystoneInfo()
        if slottedLevel and slottedLevel > 0 then
            diffText = "Mythic +" .. tostring(slottedLevel)
        end
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
sfui_events.RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED", function()
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

if sfui.RegisterModule then
    sfui.location = sfui.location or {}
    sfui.location.GetDebugInfo = sfui.location_debug_info
    sfui.RegisterModule("location", sfui.location)
end
