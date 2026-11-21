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
local ipairs = _G.ipairs
local table_insert, table_wipe = _G.table.insert, _G.wipe
local math_max = _G.math.max

local BOONS_SPELL_IDS = {
    1280098, -- Delves & Labyrinths Boons
    1229266, -- Blessing of Abundance (Midnight World Event)
}
local DEFAULT_WIDTH = 280

local boonsFrame = nil
local rowPool = {}
local activeRows = {}
local currentAuraInstanceID = nil
local currentSpellID = nil
local pendingUpdate = false
local updateTimer = nil
local needsUpdateAfterCombat = false
local DeferBoonsUpdate

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
    return sfui.common.get_scan_tooltip()
end

local function AreAurasSecret()
    local cSecrets = _G.C_Secrets
    return cSecrets and cSecrets.ShouldAurasBeSecret and cSecrets.ShouldAurasBeSecret() or false
end

-- ─── Aura Lookup ─────────────────────────────────────────────────────────────
local function FindBoonsAura()
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local checkSpellSecret = _G.C_Secrets and _G.C_Secrets.ShouldSpellAuraBeSecret
        for _, sID in ipairs(BOONS_SPELL_IDS) do
            if not (checkSpellSecret and checkSpellSecret(sID)) then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(sID)
                if aura then
                    if not aura.spellId or issecretvalue(aura.spellId) then
                        aura.spellId = sID
                    end
                    return aura
                end
            end
        end
        return nil
    end

    -- Classic / legacy fallback only when GetPlayerAuraBySpellID is unavailable
    if not AreAurasSecret() and _G.UnitBuff then
        for i = 1, 40 do
            local name, icon, count, _, _, _, _, _, _, spellID = _G.UnitBuff("player", i)
            if not name or issecretvalue(name) then break end
            if not issecretvalue(spellID) then
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

local _boonsRawLines = {}
local _boonsStats = {}

local function GetBoonsLines(aura)
    table_wipe(_boonsRawLines)
    local rawLines = _boonsRawLines
    if not aura or AreAurasSecret() then return rawLines end
    local hasPlainInstanceID = aura.auraInstanceID and not issecretvalue(aura.auraInstanceID)

    -- 1. Modern C_TooltipInfo by auraInstanceID
    if C_TooltipInfo and hasPlainInstanceID then
        local getter = C_TooltipInfo.GetUnitBuffByAuraInstanceID or C_TooltipInfo.GetUnitAuraByAuraInstanceID
        if getter then
            local data = getter("player", aura.auraInstanceID)
            if data and data.lines then
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
    if #rawLines == 0 and hasPlainInstanceID then
        local scanner = GetOrCreateScanner()
        scanner:ClearLines()
        local setter = scanner.SetUnitBuffByAuraInstanceID or scanner.SetUnitAuraByAuraInstanceID
        if setter then
            setter(scanner, "player", aura.auraInstanceID)
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
            scanner:SetUnitBuff("player", aura.index)
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
    local plainSpellID = aura.spellId and not issecretvalue(aura.spellId) and aura.spellId or BOONS_SPELL_IDS[1]
    if #rawLines == 0 and C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local data = C_TooltipInfo.GetSpellByID(plainSpellID)
        if data and data.lines then
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
    f:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
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
    sfui.common.set_square_icon_coords(icon)
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
                if not AreAurasSecret() and tip.SetUnitBuffByAuraInstanceID and currentAuraInstanceID and not issecretvalue(currentAuraInstanceID) then
                    tip:SetUnitBuffByAuraInstanceID("player", currentAuraInstanceID)
                elseif tip.SetSpellByID and currentSpellID and not issecretvalue(currentSpellID) then
                    tip:SetSpellByID(currentSpellID)
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
        DeferBoonsUpdate()
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
        boonsFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", posX, -300)
        boonsFrame:SetWidth(cfgWidth)
    end

    -- Sync palette border
    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local bCol = (pal and pal.borderColor) or { 0, 0, 0, 0.9 }
    boonsFrame:SetBackdropBorderColor(bCol[1] or 0, bCol[2] or 0, bCol[3] or 0, bCol[4] or 0.9)
end

local _auraEventRegistered = false
local UpdateAuraSubscription

-- ─── Core Content Update ─────────────────────────────────────────────────────
function Boons.Update()
    if InCombatLockdown() or AreAurasSecret() then
        DeferBoonsUpdate()
        return
    end

    if SfuiDB and SfuiDB.showBoonsDetails == false then
        if boonsFrame then boonsFrame:Hide() end
        if UpdateAuraSubscription then UpdateAuraSubscription() end
        return
    end

    local aura = FindBoonsAura()
    if not aura then
        currentAuraInstanceID = nil
        currentSpellID = nil
        if boonsFrame then boonsFrame:Hide() end
        if UpdateAuraSubscription then UpdateAuraSubscription() end
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
    local stats = _boonsStats
    local numStats = 0
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
                    numStats = numStats + 1
                    local entry = stats[numStats]
                    if not entry then
                        entry = {}
                        stats[numStats] = entry
                    end
                    entry.label = stat:lower() .. ":"
                    entry.value = val:lower()
                end
            else
                numStats = numStats + 1
                local entry = stats[numStats]
                if not entry then
                    entry = {}
                    stats[numStats] = entry
                end
                entry.label = line:lower()
                entry.value = ""
            end
        end
    end

    f.title:SetText(customTitle)

    -- Count Badge
    local appCount = aura.applications or (aura.charges and aura.charges > 0 and aura.charges) or 0
    if appCount > 1 then
        f.countText:SetFormattedText("%d stacks", appCount)
    elseif numStats > 0 then
        f.countText:SetFormattedText("%d powers", numStats)
    else
        f.countText:SetText("")
    end

    ReleaseAllRows()

    local isCollapsed = (SfuiDB and SfuiDB.boonsPanelCollapsed == true)
    local totalHeight = 32

    if isCollapsed or numStats == 0 then
        f.divider:Hide()
    else
        f.divider:Show()
        local yOffset = -34
        for i = 1, numStats do
            local sData = stats[i]
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
    if UpdateAuraSubscription then UpdateAuraSubscription() end
end

local function _execute_scheduled_boons_update()
    pendingUpdate = false
    updateTimer = nil
    if InCombatLockdown() then
        DeferBoonsUpdate()
        return
    end
    Boons.Update()
end

function Boons.RequestUpdate(delay)
    if InCombatLockdown() then
        DeferBoonsUpdate()
        return
    end
    if pendingUpdate then
        return
    end
    pendingUpdate = true
    C_Timer.After(delay or 0.05, _execute_scheduled_boons_update)
end

-- ─── Event Registration ──────────────────────────────────────────────────────
local function on_regen_disabled()
    if pendingUpdate or updateTimer then
        if updateTimer and updateTimer.Cancel then
            updateTimer:Cancel()
        end
        updateTimer = nil
        pendingUpdate = false
        -- the cancelled refresh still has to happen once combat ends
        DeferBoonsUpdate()
    end
end

local function on_regen_enabled()
    if needsUpdateAfterCombat then
        needsUpdateAfterCombat = false
        Boons.RequestUpdate(0.05)
    end
end

DeferBoonsUpdate = function()
    needsUpdateAfterCombat = true
    if InCombatLockdown() and sfui.safety and sfui.safety.DeferOutOfCombat then
        sfui.safety.DeferOutOfCombat("q_boons_update", sfui.safety.OOC_P1, on_regen_enabled)
    end
end

local on_aura_or_zone
UpdateAuraSubscription = function()
    local events = sfui.events
    if not (events and events.RegisterUnitEvent and events.UnregisterUnitEvent) then return end
    local inScenario = _G.C_Scenario and _G.C_Scenario.IsInScenario and _G.C_Scenario.IsInScenario()
    local isShown = boonsFrame and boonsFrame:IsShown()
    local want = (inScenario or isShown) and true or false
    if want and not _auraEventRegistered then
        _auraEventRegistered = true
        events.RegisterUnitEvent("UNIT_AURA", "player", on_aura_or_zone)
    elseif not want and _auraEventRegistered then
        _auraEventRegistered = false
        events.UnregisterUnitEvent("UNIT_AURA", "player", on_aura_or_zone)
    end
end

local function on_entering_world()
    UpdateAuraSubscription()
    C_Timer.After(0.5, Boons.Update)
    C_Timer.After(1.0, Boons.UpdateAnchor)
end

on_aura_or_zone = function(event)
    UpdateAuraSubscription()
    if event == "UNIT_AURA" then
        local isShown = boonsFrame and boonsFrame:IsShown()
        if not isShown and not FindBoonsAura() then
            return
        end
        Boons.RequestUpdate(0.05)
    else
        Boons.RequestUpdate(0.1)
    end
end

local events = sfui.events
events.RegisterEvent("PLAYER_ENTERING_WORLD", on_entering_world)
events.RegisterEvent("PLAYER_REGEN_DISABLED", on_regen_disabled)
events.RegisterEvent("SCENARIO_UPDATE", on_aura_or_zone)
events.RegisterEvent("SCENARIO_CRITERIA_UPDATE", on_aura_or_zone)
events.RegisterEvent("ZONE_CHANGED_NEW_AREA", on_aura_or_zone)
events.RegisterEvent("ZONE_CHANGED", on_aura_or_zone)
UpdateAuraSubscription()

-- Safe Theme Registration
if sfui.theme and sfui.theme.RegisterThemeCallback then
    sfui.theme.RegisterThemeCallback(function()
        if boonsFrame and boonsFrame:IsShown() then
            Boons.UpdateAnchor()
        end
    end)
end
