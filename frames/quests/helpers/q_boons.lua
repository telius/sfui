local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.boons = sfui.tracker.boons or {}

local Boons = sfui.tracker.boons

-- ==============================================================================
--  sfui/frames/quests/helpers/q_boons.lua
--  Delve & Labyrinth Boons Buff (1280098) Display Panel
-- ==============================================================================

local _G = _G
local UIParent = _G.UIParent
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local C_UnitAuras = _G.C_UnitAuras
local C_TooltipInfo = _G.C_TooltipInfo
local C_Timer = _G.C_Timer
local ipairs, pairs, type = _G.ipairs, _G.pairs, _G.type
local table_insert, table_wipe = _G.table.insert, _G.wipe
local math_max, math_min = _G.math.max, _G.math.min
local tostring = _G.tostring

local BOONS_SPELL_IDS = {
    1280098, -- Delves & Labyrinths Boons
    1229266, -- Blessing of Abundance (Midnight World Event)
}
local DEFAULT_WIDTH = 280

local boonsFrame = nil
local rowPool = {}
local activeRows = {}
local scanTooltip = nil
local currentAuraInstanceID = nil
local currentSpellID = nil
local pendingUpdate = false
local updateTimer = nil
local needsUpdateAfterCombat = false

local function issecretvalue(val)
    if sfui.common and sfui.common.issecretvalue then
        return sfui.common.issecretvalue(val)
    end
    if _G.issecretvalue then
        return _G.issecretvalue(val)
    end
    return false
end

-- ─── Tooltip Scanner Fallback ────────────────────────────────────────────────
local function GetOrCreateScanner()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "SfuiBoonsScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

-- ─── Aura Lookup ─────────────────────────────────────────────────────────────
local function FindBoonsAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, sID in ipairs(BOONS_SPELL_IDS) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sID)
            if ok and aura then
                aura.spellId = aura.spellId or sID
                return aura
            end
        end
        return nil
    end

    -- Classic / legacy fallback only when GetPlayerAuraBySpellID is unavailable
    if _G.UnitBuff then
        for i = 1, 40 do
            local ok, name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID = pcall(_G.UnitBuff, "player", i)
            if not ok or not name then break end
            for _, sID in ipairs(BOONS_SPELL_IDS) do
                if spellID == sID then
                    return {
                        name = name,
                        icon = icon,
                        spellId = spellID,
                        applications = count,
                        auraInstanceID = nil,
                        index = i,
                    }
                end
            end
        end
    end

    return nil
end

-- ─── Tooltip Data Extraction ─────────────────────────────────────────────────
local function IsSpellIDLine(line)
    if not line or line == "" then return true end
    local l = line:lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Exact number only (e.g. "1280098")
    if tonumber(l) then return true end
    -- "spellid: 12345", "spell id: 12345", "spellid 12345", "spell id 12345"
    if l:find("^spell%s*id") then return true end
    -- "id: 12345", "id 12345"
    if l:match("^id%s*:%s*%d+") or l:match("^id%s+%d+") then return true end
    -- "spell: 12345"
    if l:match("^spell%s*:%s*%d+") or l:match("^spell%s+%d+") then return true end
    -- "aura id: 12345", "aura: 12345", "auraid: 12345", "aurainstanceid: 12345"
    if l:find("^aura%s*id") or l:match("^aura%s*:%s*%d+") or l:find("^aurainstanceid") then return true end
    return false
end

local function GetBoonsLines(aura)
    local rawLines = {}
    if not aura then return rawLines end

    -- 1. Modern C_TooltipInfo by auraInstanceID
    if C_TooltipInfo and aura.auraInstanceID then
        local getter = C_TooltipInfo.GetUnitBuffByAuraInstanceID or C_TooltipInfo.GetUnitAuraByAuraInstanceID
        if getter then
            local ok, data = pcall(getter, "player", aura.auraInstanceID)
            if ok and data and data.lines then
                for _, l in ipairs(data.lines) do
                    local txt = l.leftText
                    if txt and txt ~= "" and not issecretvalue(txt) then
                        for line in txt:gmatch("[^\r\n]+") do
                            local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
                            if clean ~= "" and not IsSpellIDLine(clean) then
                                table_insert(rawLines, clean)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Fallback: GameTooltip Scanner using SetUnitBuffByAuraInstanceID
    if #rawLines == 0 and aura.auraInstanceID then
        local scanner = GetOrCreateScanner()
        scanner:ClearLines()
        local setter = scanner.SetUnitBuffByAuraInstanceID or scanner.SetUnitAuraByAuraInstanceID
        if setter then
            pcall(setter, scanner, "player", aura.auraInstanceID)
            local num = scanner:NumLines() or 0
            for i = 1, num do
                local fs = _G[scanner:GetName() .. "TextLeft" .. i]
                local txt = fs and fs:GetText()
                if txt and txt ~= "" and not issecretvalue(txt) then
                    for line in txt:gmatch("[^\r\n]+") do
                        local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
                        if clean ~= "" and not IsSpellIDLine(clean) then
                            table_insert(rawLines, clean)
                        end
                    end
                end
            end
        end
    end

    -- 3. Fallback: Classic UnitBuff scanner
    if #rawLines == 0 and aura.index then
        local scanner = GetOrCreateScanner()
        scanner:ClearLines()
        if scanner.SetUnitBuff then
            pcall(scanner.SetUnitBuff, scanner, "player", aura.index)
        end
        local num = scanner:NumLines() or 0
        for i = 1, num do
            local fs = _G[scanner:GetName() .. "TextLeft" .. i]
            local txt = fs and fs:GetText()
            if txt and txt ~= "" and not issecretvalue(txt) then
                for line in txt:gmatch("[^\r\n]+") do
                    local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if clean ~= "" and not IsSpellIDLine(clean) then
                        table_insert(rawLines, clean)
                    end
                end
            end
        end
    end

    -- 4. Fallback: Spell ID description if aura tooltip was completely empty
    if #rawLines == 0 and C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local ok, data = pcall(C_TooltipInfo.GetSpellByID, BOONS_SPELL_ID)
        if ok and data and data.lines then
            for _, l in ipairs(data.lines) do
                local txt = l.leftText
                if txt and txt ~= "" and not issecretvalue(txt) then
                    for line in txt:gmatch("[^\r\n]+") do
                        local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
                        if clean ~= "" and not IsSpellIDLine(clean) then
                            table_insert(rawLines, clean)
                        end
                    end
                end
            end
        end
    end

    return rawLines
end

-- ─── Row Pool ────────────────────────────────────────────────────────────────
local function AcquireRow(parent)
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(15)

        local leftText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        leftText:SetPoint("LEFT", row, "LEFT", 8, 0)
        leftText:SetJustifyH("LEFT")
        leftText:SetTextColor(0.82, 0.82, 0.84, 1.0)
        row.leftText = leftText

        local rightText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rightText:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        rightText:SetJustifyH("RIGHT")
        rightText:SetTextColor(0.40, 1.00, 0.60, 1.0) -- Soft bright green for values
        row.rightText = rightText
    else
        row:SetParent(parent)
    end

    row:Show()
    table_insert(activeRows, row)
    return row
end

local function ReleaseAllRows()
    for _, row in ipairs(activeRows) do
        row:Hide()
        row:ClearAllPoints()
        table_insert(rowPool, row)
    end
    table_wipe(activeRows)
end

-- ─── Frame Construction ──────────────────────────────────────────────────────
local function GetOrCreateBoonsFrame()
    if boonsFrame then return boonsFrame end

    local f = CreateFrame("Frame", "SfuiBoonsFrame", UIParent, "BackdropTemplate")
    f:SetSize(DEFAULT_WIDTH, 80)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)

    -- Backdrop matching delve / mythic tracker
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.88)
    f:SetBackdropBorderColor(0, 0, 0, 0.9)

    -- Header Icon
    local iconFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    iconFrame:SetSize(16, 16)
    iconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.texture = icon
    f.iconFrame = iconFrame

    -- Header Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
    title:SetTextColor(1.00, 0.82, 0.00, 1.0) -- Gold/yellow
    title:SetText("boons")
    f.title = title

    -- Header Count / Details
    local countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    countText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    countText:SetTextColor(0.60, 0.60, 0.65, 1.0)
    f.countText = countText

    -- Divider Line
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -28)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -28)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.08)
    f.divider = divider

    -- Tooltip Hover: Show Blizzard Aura Tooltip
    f:SetScript("OnEnter", function(self)
        if currentAuraInstanceID or currentSpellID then
            local tip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_LEFT", -8, 0)
                if tip.SetUnitBuffByAuraInstanceID and currentAuraInstanceID then
                    pcall(tip.SetUnitBuffByAuraInstanceID, tip, "player", currentAuraInstanceID)
                elseif tip.SetSpellByID and currentSpellID then
                    pcall(tip.SetSpellByID, tip, currentSpellID)
                end
                tip:Show()
            end
        end
    end)

    f:SetScript("OnLeave", function(self)
        local tip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or _G.GameTooltip
        if tip then tip:Hide() end
    end)

    -- Click Header to Toggle Collapsed State
    f:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            if InCombatLockdown() then return end
            if SfuiDB then
                SfuiDB.boonsPanelCollapsed = not SfuiDB.boonsPanelCollapsed
                Boons.Update()
            end
        end
    end)

    f:Hide()
    boonsFrame = f

    if Boons.EnsureDelveHUDHooked then
        Boons.EnsureDelveHUDHooked()
    end

    return f
end

-- ─── Delve HUD Hooking Helper ────────────────────────────────────────────────
local function EnsureDelveHUDHooked()
    local mythicHud = _G.SfuiMythicHUD
    if mythicHud and not mythicHud._sfuiBoonsHooked then
        mythicHud._sfuiBoonsHooked = true
        mythicHud:HookScript("OnSizeChanged", function()
            Boons.UpdateAnchor()
        end)
        mythicHud:HookScript("OnShow", function()
            Boons.UpdateAnchor()
        end)
        mythicHud:HookScript("OnHide", function()
            Boons.UpdateAnchor()
        end)
    end
end
Boons.EnsureDelveHUDHooked = EnsureDelveHUDHooked

-- ─── Anchor Update ───────────────────────────────────────────────────────────
function Boons.UpdateAnchor()
    if InCombatLockdown() then
        needsUpdateAfterCombat = true
        return
    end
    if not boonsFrame or not boonsFrame:IsShown() then return end

    EnsureDelveHUDHooked()

    local mythicHud = _G.SfuiMythicHUD
    local tracker = _G.SfuiQuestTrackerFrame
    local otf = _G.ObjectiveTrackerFrame
    local target = nil

    local isMythicActive = (sfui.mythic and sfui.mythic.IsActive and sfui.mythic.IsActive())
        or (mythicHud and mythicHud:IsShown() and mythicHud:GetAlpha() > 0)

    -- Priority 1: Delve / Mythic HUD when actively displaying Delve or Scenario objectives
    if isMythicActive and mythicHud and mythicHud:IsShown() then
        target = mythicHud
    elseif tracker and tracker:IsShown() and (tracker:GetAlpha() or 1) > 0 and tracker:GetHeight() > 20 then
        target = tracker
    elseif otf and otf:IsShown() and (otf:GetAlpha() or 1) > 0 and otf:GetHeight() > 20 then
        target = otf
    elseif tracker and tracker:IsShown() and (tracker:GetAlpha() or 1) > 0 then
        target = tracker
    elseif otf and otf:IsShown() then
        target = otf
    elseif mythicHud and mythicHud:IsShown() then
        target = mythicHud
    else
        target = UIParent
    end

    local cfgWidth = (sfui.config and sfui.config.questlog and sfui.config.questlog.width) or DEFAULT_WIDTH

    boonsFrame:ClearAllPoints()
    if target and target ~= UIParent then
        -- Match exact width and left/right horizontal bounds with 4px gap underneath
        boonsFrame:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -4)
        boonsFrame:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, -4)
        local tW = target:GetWidth()
        if tW and tW > 20 then
            boonsFrame:SetWidth(tW)
        end
    else
        local posX = (SfuiDB and (SfuiDB.mythicHudX or SfuiDB.questlogX)) or -4
        local posY = (SfuiDB and (SfuiDB.mythicHudY or SfuiDB.questlogY)) or -4
        boonsFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", posX, -300)
        boonsFrame:SetWidth(cfgWidth)
    end

    -- Sync palette border
    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local bCol = (pal and pal.borderColor) or { 0, 0, 0, 0.9 }
    boonsFrame:SetBackdropBorderColor(bCol[1] or 0, bCol[2] or 0, bCol[3] or 0, bCol[4] or 0.9)
end

-- ─── Core Content Update ─────────────────────────────────────────────────────
function Boons.Update()
    if InCombatLockdown() then
        needsUpdateAfterCombat = true
        return
    end

    if SfuiDB and SfuiDB.showBoonsDetails == false then
        if boonsFrame then boonsFrame:Hide() end
        return
    end

    local aura = FindBoonsAura()
    if not aura then
        currentAuraInstanceID = nil
        currentSpellID = nil
        if boonsFrame then boonsFrame:Hide() end
        return
    end

    currentAuraInstanceID = aura.auraInstanceID
    currentSpellID = aura.spellId or aura.spellID
    local f = GetOrCreateBoonsFrame()

    -- Set Icon
    local iconTex = aura.icon or "Interface\\Icons\\Spell_holy_magicalsentry"
    f.iconFrame.texture:SetTexture(iconTex)

    -- Extract Lines
    local rawLines = GetBoonsLines(aura)
    local stats = {}
    local customTitle = "boons"

    for idx, line in ipairs(rawLines) do
        local lClean = line:lower()
        if idx == 1 and (lClean == "boons" or lClean == (aura.name and aura.name:lower())) then
            customTitle = lClean
        elseif not IsSpellIDLine(line) then
            -- Match "Stat Name: Value"
            local stat, val = line:match("^([^:]+):%s*(.+)$")
            if stat and val then
                local sLow = stat:lower():gsub("^%s+", ""):gsub("%s+$", "")
                if sLow == "spellid" or sLow == "spell id" or sLow == "spell" or sLow == "id" or sLow == "aura id" or sLow == "aurainstanceid" or sLow == "aura" then
                    -- Skip spell ID / aura ID lines
                else
                    val = val:gsub("%.$", "")
                    table_insert(stats, {
                        label = stat:lower() .. ":",
                        value = val:lower(),
                    })
                end
            else
                table_insert(stats, {
                    label = line:lower(),
                    value = "",
                })
            end
        end
    end

    f.title:SetText(customTitle)

    -- Count Badge
    local appCount = aura.applications or (aura.charges and aura.charges > 0 and aura.charges) or 0
    if appCount > 1 then
        f.countText:SetFormattedText("%d stacks", appCount)
    elseif #stats > 0 then
        f.countText:SetFormattedText("%d powers", #stats)
    else
        f.countText:SetText("")
    end

    ReleaseAllRows()

    local isCollapsed = (SfuiDB and SfuiDB.boonsPanelCollapsed == true)
    local totalHeight = 32

    if isCollapsed or #stats == 0 then
        f.divider:Hide()
    else
        f.divider:Show()
        local yOffset = -34
        for _, sData in ipairs(stats) do
            local row = AcquireRow(f)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, yOffset)
            row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, yOffset)

            row.leftText:SetText(sData.label)
            if sData.value ~= "" then
                row.rightText:SetText(sData.value)
                row.rightText:Show()
            else
                row.rightText:Hide()
            end

            yOffset = yOffset - 17
        end
        totalHeight = math_max(32, math.abs(yOffset) + 8)
    end

    f:SetHeight(totalHeight)
    f:Show()
    Boons.UpdateAnchor()
end

function Boons.RequestUpdate(delay)
    if InCombatLockdown() then
        needsUpdateAfterCombat = true
        return
    end
    if updateTimer then
        updateTimer:Cancel()
        updateTimer = nil
    end
    updateTimer = C_Timer.NewTimer(delay or 0.05, function()
        updateTimer = nil
        if InCombatLockdown() then
            needsUpdateAfterCombat = true
            return
        end
        Boons.Update()
    end)
end

-- ─── Event Registration ──────────────────────────────────────────────────────
local function on_regen_disabled()
    if updateTimer then
        updateTimer:Cancel()
        updateTimer = nil
        -- the cancelled refresh still has to happen once combat ends
        needsUpdateAfterCombat = true
    end
end

local function on_regen_enabled()
    if needsUpdateAfterCombat then
        needsUpdateAfterCombat = false
        Boons.RequestUpdate(0.05)
    end
end

local function on_entering_world()
    C_Timer.After(0.5, Boons.Update)
    C_Timer.After(1.0, Boons.UpdateAnchor)
end

local function on_aura_or_zone(event)
    Boons.RequestUpdate(event == "UNIT_AURA" and 0.05 or 0.1)
end

local events = sfui.events
events.RegisterEvent("PLAYER_ENTERING_WORLD", on_entering_world)
events.RegisterEvent("PLAYER_REGEN_DISABLED", on_regen_disabled)
events.RegisterEvent("PLAYER_REGEN_ENABLED", on_regen_enabled)
events.RegisterUnitEvent("UNIT_AURA", "player", on_aura_or_zone)
events.RegisterEvent("SCENARIO_UPDATE", on_aura_or_zone)
events.RegisterEvent("SCENARIO_CRITERIA_UPDATE", on_aura_or_zone)
events.RegisterEvent("ZONE_CHANGED_NEW_AREA", on_aura_or_zone)
events.RegisterEvent("ZONE_CHANGED", on_aura_or_zone)

-- Safe Theme Registration
if sfui.theme and sfui.theme.RegisterThemeCallback then
    sfui.theme.RegisterThemeCallback(function()
        if boonsFrame and boonsFrame:IsShown() then
            Boons.UpdateAnchor()
        end
    end)
end
