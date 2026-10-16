local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = sfui.minimap or {}

local _G = _G
local date = _G.date
local math = _G.math
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local table = _G.table
local pcall = _G.pcall
local collectgarbage = _G.collectgarbage
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local GetFramerate = _G.GetFramerate
local GetNetStats = _G.GetNetStats
local GetAddOnMemoryUsage = _G.GetAddOnMemoryUsage
local UpdateAddOnMemoryUsage = _G.UpdateAddOnMemoryUsage
local GameTooltip = _G.GameTooltip
local PlaySound = _G.PlaySound
local SOUNDKIT = _G.SOUNDKIT or {}

local C_AddOns = _G.C_AddOns
local GetNumAddOns = (C_AddOns and C_AddOns.GetNumAddOns) or _G.GetNumAddOns
local GetAddOnInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
local IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded

local system_btn = nil
local update_timer = 0
local COMBINE_ADDONS = {
    ["Details"]      = "^Details",
    ["DBM"]          = "^DBM",
    ["BigWigs"]      = "^BigWigs",
    ["LittleWigs"]   = "^LittleWigs",
    ["RaiderIO"]     = "^RaiderIO",
    ["Altoholic"]    = "^Altoholic",
    ["DataStore"]    = "^DataStore",
    ["WeakAuras"]    = "^WeakAuras",
    ["Auctionator"]  = "^Auctionator",
    ["HandyNotes"]   = "^HandyNotes",
    ["Plater"]       = "^Plater",
    ["TomTom"]       = "^TomTom",
    ["Questie"]      = "^Questie",
}

local function format_mem(kb)
    if not kb or kb <= 0 then return "0 kb" end
    if kb >= 1024 then
        return string.format("%.2f mb", kb / 1024)
    else
        return string.format("%d kb", math.floor(kb + 0.5))
    end
end

local function get_current_time_string()
    if _G.GameTime_GetTime then
        local ok, str = pcall(_G.GameTime_GetTime, false)
        if ok and str and str ~= "" then return str end
    end
    return date("%H:%M")
end

local function get_system_stats()
    local fps = math.floor((GetFramerate and GetFramerate() or 0) + 0.5)
    local homePing, worldPing = 0, 0
    if GetNetStats then
        local _, _, hp, wp = GetNetStats()
        homePing = hp or 0
        worldPing = wp or 0
    end
    local ping = worldPing > 0 and worldPing or homePing
    return fps, ping, homePing, worldPing
end

function sfui.minimap.get_system_mode()
    if SfuiDB and SfuiDB.minimap_system_mode then
        return SfuiDB.minimap_system_mode
    end
    return "system"
end

function sfui.minimap.cycle_system_mode()
    local current = sfui.minimap.get_system_mode()
    local nextMode = (current == "system") and "clock" or "system"
    if SfuiDB then
        SfuiDB.minimap_system_mode = nextMode
    end
    if PlaySound then
        pcall(PlaySound, SOUNDKIT.U_CHAT_SCROLL_BUTTON or 1115)
    end
    sfui.minimap.update_system_button()
    if sfui.minimap.arrange_buttons then
        sfui.minimap.arrange_buttons()
    end
end

local function update_tooltip(btn)
    if not btn or not btn.isHovered then return end
    GameTooltip:SetOwner(btn, "ANCHOR_LEFT", -4, 0)
    GameTooltip:ClearLines()

    GameTooltip:AddDoubleLine("|cff6600ffsf|rui system", date("%A, %B %d"), 1, 1, 1, 0.7, 0.7, 0.7)

    local localTime = _G.GameTime_GetLocalTime and _G.GameTime_GetLocalTime(true)
    local realmTime = _G.GameTime_GetGameTime and _G.GameTime_GetGameTime(true)
    if localTime and realmTime then
        GameTooltip:AddDoubleLine("local time:", localTime, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("realm time:", realmTime, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    local fps, ping, homePing, worldPing = get_system_stats()
    GameTooltip:AddDoubleLine("framerate:", string.format("%d fps", fps), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("home latency:", string.format("%d ms", homePing), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("world latency:", string.format("%d ms", worldPing), 0.8, 0.8, 0.8, 1, 1, 1)

    if UpdateAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
    end

    local addonCount = (GetNumAddOns and GetNumAddOns()) or 0
    local list = {}
    local combined = {}
    local totalAddonMem = 0

    for i = 1, addonCount do
        local isLoaded = IsAddOnLoaded and IsAddOnLoaded(i)
        if isLoaded then
            local name, title = GetAddOnInfo(i)
            name = name or ("addon" .. i)
            local mem = (GetAddOnMemoryUsage and GetAddOnMemoryUsage(i)) or 0
            totalAddonMem = totalAddonMem + mem

            local matchedGroup = nil
            for groupName, pattern in pairs(COMBINE_ADDONS) do
                if name:find(pattern) then
                    matchedGroup = groupName
                    break
                end
            end

            if matchedGroup then
                if not combined[matchedGroup] then
                    combined[matchedGroup] = { name = matchedGroup, displayName = matchedGroup, mem = 0, isGroup = true }
                    list[#list + 1] = combined[matchedGroup]
                end
                combined[matchedGroup].mem = combined[matchedGroup].mem + mem
            else
                local cleanTitle = title and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
                local displayName = (cleanTitle and cleanTitle ~= "") and cleanTitle or name
                list[#list + 1] = { name = name, displayName = displayName, mem = mem }
            end
        end
    end

    table.sort(list, function(a, b)
        return (a.mem or 0) > (b.mem or 0)
    end)

    local totalLuaMem = collectgarbage("count")
    GameTooltip:AddDoubleLine("addon memory:", format_mem(totalAddonMem), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("total lua memory:", format_mem(totalLuaMem), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(" ")

    local showAll = IsShiftKeyDown()
    local maxDisplay = showAll and #list or 15
    local displayed = math.min(#list, maxDisplay)

    for i = 1, displayed do
        local item = list[i]
        local isSfui = (item.name:lower() == "sfui")
        if isSfui then
            GameTooltip:AddDoubleLine("|cff6600ffsf|rui", format_mem(item.mem), 1, 1, 1, 0.8, 0.6, 1.0)
        else
            GameTooltip:AddDoubleLine(item.displayName, format_mem(item.mem), 0.85, 0.85, 0.85, 0.95, 0.95, 0.95)
        end
    end

    if #list > displayed then
        GameTooltip:AddLine(string.format("|cff888888... and %d more (hold shift to show all)|r", #list - displayed))
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff888888<left-click>|r cycle clock / stats")
    GameTooltip:AddLine("|cff888888<right-click>|r toggle stopwatch & alarm")
    GameTooltip:AddLine("|cff888888<middle-click>|r toggle calendar")
    GameTooltip:AddLine("|cff888888<shift-click>|r clean memory & collect garbage")
    GameTooltip:Show()
end

local function on_click(self, button)
    if IsShiftKeyDown() then
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        local freed = before - after
        local freedStr = (freed >= 1024) and string.format("%.2f mb", freed / 1024) or string.format("%d kb", math.max(0, math.floor(freed + 0.5)))
        print(string.format("|cff6600ffsf|rui: collected garbage, freed %s memory.", freedStr))
        if PlaySound then
            pcall(PlaySound, SOUNDKIT.IG_MINIMAP_ZOOM_IN or 856)
        end
        if self.isHovered then
            update_tooltip(self)
        end
        return
    end

    if button == "LeftButton" then
        sfui.minimap.cycle_system_mode()
    elseif button == "RightButton" then
        if _G.TimeManager_Toggle then
            _G.TimeManager_Toggle()
        elseif _G.UIParentLoadAddOn and pcall(_G.UIParentLoadAddOn, "Blizzard_TimeManager") and _G.TimeManager_Toggle then
            _G.TimeManager_Toggle()
        end
    elseif button == "MiddleButton" then
        if _G.ToggleCalendar then
            _G.ToggleCalendar()
        end
    end
end

local function get_spec_color_hex()
    if sfui.colors and sfui.colors.get_class_or_spec_color then
        local c = sfui.colors.get_class_or_spec_color()
        if c then
            local r = math.floor((c[1] or c.r or 1) * 255 + 0.5)
            local g = math.floor((c[2] or c.g or 1) * 255 + 0.5)
            local b = math.floor((c[3] or c.b or 1) * 255 + 0.5)
            return string.format("|cff%02x%02x%02x", r, g, b)
        end
    end
    if sfui.common and sfui.common.get_class_or_spec_color then
        local c = sfui.common.get_class_or_spec_color()
        if c then
            local r = math.floor((c[1] or c.r or 1) * 255 + 0.5)
            local g = math.floor((c[2] or c.g or 1) * 255 + 0.5)
            local b = math.floor((c[3] or c.b or 1) * 255 + 0.5)
            return string.format("|cff%02x%02x%02x", r, g, b)
        end
    end
    return "|cff00e5ff"
end

function sfui.minimap.init_system_button(parent)
    if system_btn then
        if parent and system_btn:GetParent() ~= parent then
            system_btn:SetParent(parent)
        end
        return system_btn
    end

    local btn = CreateFrame("Button", "SfuiMinimapSystemButton", parent or Minimap)
    system_btn = btn
    sfui.minimap.system_button = btn

    btn:RegisterForClicks("AnyUp")
    btn:SetHeight(20)

    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or (sfui.config and sfui.config.font)
        or "Fonts\\FRIZQT__.TTF"

    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont(fontFile, 12, "")
    btn.text:SetShadowOffset(0, 0)
    btn.text:SetShadowColor(0, 0, 0, 0)
    btn.text:SetTextColor(0.9, 0.9, 0.9, 1)
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)

    btn:SetScript("OnClick", on_click)

    btn:SetScript("OnEnter", function(self)
        self.isHovered = true
        update_tooltip(self)
    end)

    btn:SetScript("OnLeave", function(self)
        self.isHovered = false
        GameTooltip:Hide()
    end)

    btn:SetScript("OnUpdate", function(self, elapsed)
        update_timer = update_timer + elapsed
        if update_timer >= 1.0 then
            update_timer = 0
            sfui.minimap.update_system_button()
            if self.isHovered then
                update_tooltip(self)
            end
        end
    end)

    btn:RegisterEvent("MODIFIER_STATE_CHANGED")
    btn:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    btn:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            sfui.minimap.update_system_button()
        elseif self.isHovered then
            update_tooltip(self)
        end
    end)

    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_SPEC_COLORS_UPDATED", function()
            sfui.minimap.update_system_button()
        end)
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function()
            sfui.minimap.update_system_button()
        end)
    end

    return btn
end

function sfui.minimap.update_system_button(buttonBar)
    local parent = buttonBar or sfui.minimap.button_bar
    if not parent then return end

    local btn = sfui.minimap.init_system_button(parent)
    btn:SetParent(parent)
    btn:SetFrameStrata(parent:GetFrameStrata())
    btn:SetFrameLevel(parent:GetFrameLevel() + 5)

    local mode = sfui.minimap.get_system_mode()
    local displayStr = ""
    if mode == "clock" then
        displayStr = get_current_time_string()
    else
        local fps, ping = get_system_stats()
        local specHex = get_spec_color_hex()
        displayStr = string.format("%d %sfps|r  %d %sms|r", fps, specHex, ping, specHex)
    end

    btn.text:SetText(displayStr)
    local textW = (btn.text.GetStringWidth and btn.text:GetStringWidth()) or 44
    local btnW = math.max(48, textW + 8)
    btn:SetSize(btnW, 20)

    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", parent, "RIGHT", -8, 2)
    btn:Show()

    local clock = _G.TimeManagerClockButton
    if clock and clock.Hide then
        clock:Hide()
    end
end
