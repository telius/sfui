local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.tooltip = {}

local tooltip = sfui.experience.tooltip

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/tooltip.lua
--  Rich inspection tooltip & chat sharing for experience and reputation
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local string_format = string.format
local UnitClass = _G.UnitClass
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatFrame_OpenChat = _G.ChatFrame_OpenChat

local function GetTooltip()
    return (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip or _G.GameTooltip
end

--- Show rich inspection tooltip when hovering experience/reputation bar
--- @param anchorFrame Frame
--- @param explicitMode string|nil "XP" or "REP"
function tooltip.OnEnter(anchorFrame, explicitMode)
    if not anchorFrame then return end

    local data = sfui.experience.data
    if not data then return end

    local bar = sfui.experience.bar
    local mode = explicitMode or (bar and bar.GetMode and bar.GetMode()) or "XP"

    local tip = GetTooltip()
    tip:SetOwner(anchorFrame, "ANCHOR_TOP", 0, 6)
    tip:ClearLines()

    if mode == "REP" then
        local rep = data.GetReputationData()
        if not rep or not rep.hasRep then
            tip:AddLine("reputation", 1, 1, 1)
            tip:AddLine("no faction currently being tracked", 0.7, 0.7, 0.7)
            tip:Show()
            return
        end

        local col = rep.color or { 0, 0.8, 0.4 }
        tip:AddDoubleLine(rep.name, rep.standingText, col[1], col[2], col[3], col[1], col[2], col[3])
        tip:AddLine(" ")

        -- Progress details
        local curStr = data.FormatCommas(rep.current)
        local maxStr = data.FormatCommas(rep.max)
        tip:AddDoubleLine("standing progress:", string_format("%s / %s (%.1f%%)", curStr, maxStr, rep.percent), 0.85, 0.85, 0.85, 1, 1, 1)
        tip:AddDoubleLine("remaining to next:", string_format("%s", data.FormatCommas(rep.remaining)), 0.85, 0.85, 0.85, 1, 0.8, 0.2)

        if rep.hasRewardPending then
            tip:AddLine(" ")
            tip:AddLine("paragon reward ready to claim!", 0.2, 1.0, 0.2)
        end

    else
        -- Experience Mode
        local xp = data.GetXPData()
        local rested = data.GetRestedData(xp.max)
        local quest = data.GetQuestXPData(xp.max)
        local session = data.GetSessionStats(xp.remaining)

        local _, className = UnitClass("player")
        local classColor = (_G.RAID_CLASS_COLORS and className and _G.RAID_CLASS_COLORS[className]) or { r = 0.6, g = 0.2, b = 1.0 }

        -- Title line
        local titleStr = string_format("level %d", xp.level)
        if xp.isMaxLevel then
            titleStr = string_format("level %d (max level)", xp.level)
        end
        tip:AddDoubleLine(titleStr, className and className:lower() or "player", classColor.r, classColor.g, classColor.b, classColor.r, classColor.g, classColor.b)
        tip:AddLine(" ")

        -- Progress
        local curStr = data.FormatCommas(xp.current)
        local maxStr = data.FormatCommas(xp.max)
        tip:AddDoubleLine("current progress:", string_format("%s / %s (%.1f%%)", curStr, maxStr, xp.percent), 0.85, 0.85, 0.85, 1, 1, 1)
        tip:AddDoubleLine("remaining to level:", string_format("%s", data.FormatCommas(xp.remaining)), 0.85, 0.85, 0.85, 1, 0.82, 0.2)

        -- Rested bonus
        if rested.isRested then
            tip:AddDoubleLine("rested bonus:", string_format("%s (+%.1f%%)", data.FormatCommas(rested.restedXP), rested.restedPercent), 0.85, 0.85, 0.85, 0.2, 0.85, 1.0)
        end

        -- Completed quests in log
        if quest.completedCount > 0 then
            tip:AddLine(" ")
            tip:AddDoubleLine(string_format("completed quests (%d):", quest.completedCount), string_format("+%s (+%.1f%%)", data.FormatCommas(quest.totalQuestXP), quest.questPercent), 0.85, 0.85, 0.85, 1.0, 0.75, 0.2)
            local projectedTotal = math.min(xp.max, xp.current + quest.totalQuestXP)
            local projectedPct = math.min(100, (projectedTotal / xp.max) * 100)
            tip:AddDoubleLine("after turn-ins:", string_format("%s / %s (%.1f%%)", data.FormatCommas(projectedTotal), maxStr, projectedPct), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
        end

        -- Session Analytics
        tip:AddLine(" ")
        tip:AddLine("session analytics", 0.6, 0.6, 0.6)
        tip:AddDoubleLine("session duration:", data.FormatTime(session.sessionTime), 0.85, 0.85, 0.85, 1, 1, 1)
        tip:AddDoubleLine("xp gained this session:", string_format("+%s", data.FormatCommas(session.sessionXP)), 0.85, 0.85, 0.85, 0.3, 1.0, 0.3)

        if session.xpHour > 0 then
            tip:AddDoubleLine("session rate:", string_format("%s xp/hr", data.FormatCommas(session.xpHour)), 0.85, 0.85, 0.85, 0.3, 1.0, 0.8)
        end

        if session.ttlSeconds then
            tip:AddDoubleLine("time to level:", data.FormatTime(session.ttlSeconds), 0.85, 0.85, 0.85, 1.0, 0.85, 0.2)
        end

        if session.killsToLevel then
            tip:AddDoubleLine("estimated mob kills:", string_format("~%d kills (avg %s xp)", session.killsToLevel, data.FormatNumber(session.averageKillXP)), 0.85, 0.85, 0.85, 0.85, 0.85, 0.85)
        end
    end

    -- Interaction Footer
    tip:AddLine(" ")
    tip:AddLine("<shift-click to share progress in chat>", 0.5, 0.5, 0.5)
    tip:AddLine("<right-click to open experience settings>", 0.5, 0.5, 0.5)

    tip:Show()
end

--- Show experience tooltip specifically
--- @param anchorFrame Frame
function tooltip.OnEnterXP(anchorFrame)
    tooltip.OnEnter(anchorFrame, "XP")
end

--- Show reputation tooltip specifically
--- @param anchorFrame Frame
function tooltip.OnEnterRep(anchorFrame)
    tooltip.OnEnter(anchorFrame, "REP")
end

--- Hide inspection tooltip
function tooltip.OnLeave()
    if sfui.common and sfui.common.hide_tooltip then
        sfui.common.hide_tooltip()
    else
        local tip = GetTooltip()
        if tip and tip:IsShown() then tip:Hide() end
    end
end

--- Share current progress summary into chat (on shift-click)
--- @param explicitMode string|nil "XP" or "REP"
function tooltip.ShareToChat(explicitMode)
    local data = sfui.experience.data
    if not data then return end

    local bar = sfui.experience.bar
    local mode = explicitMode or (bar and bar.GetMode and bar.GetMode()) or "XP"
    local message = ""

    if mode == "REP" then
        local rep = data.GetReputationData()
        if not rep or not rep.hasRep then return end
        message = string_format("sfui: %s (%s) — %s / %s (%.1f%%) — %s remaining",
            rep.name,
            rep.standingText,
            data.FormatNumber(rep.current),
            data.FormatNumber(rep.max),
            rep.percent,
            data.FormatNumber(rep.remaining)
        )
    else
        local xp = data.GetXPData()
        local rested = data.GetRestedData(xp.max)
        local quest = data.GetQuestXPData(xp.max)
        local session = data.GetSessionStats(xp.remaining)
        local _, className = UnitClass("player")

        local parts = {}
        table.insert(parts, string_format("sfui: level %d %s", xp.level, className and className:lower() or "character"))
        table.insert(parts, string_format("%s/%s (%.1f%%)", data.FormatNumber(xp.current), data.FormatNumber(xp.max), xp.percent))

        if rested.isRested then
            table.insert(parts, string_format("rested: +%s", data.FormatNumber(rested.restedXP)))
        end
        if quest.completedCount > 0 then
            table.insert(parts, string_format("quests: +%s", data.FormatNumber(quest.totalQuestXP)))
        end
        if session.xpHour > 0 then
            table.insert(parts, string_format("%s xp/hr", data.FormatNumber(session.xpHour)))
        end
        if session.ttlSeconds then
            table.insert(parts, string_format("ttl: %s", data.FormatTime(session.ttlSeconds)))
        end

        message = table.concat(parts, " — ")
    end

    if not message or message == "" then return end

    -- Send to active chat editbox if open, or open chat with text pre-populated
    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if editBox and editBox:IsShown() then
        editBox:Insert(message)
    else
        if ChatFrame_OpenChat then
            ChatFrame_OpenChat(message)
        end
    end
end
