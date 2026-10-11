local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.professions = sfui.professions or {}
sfui.recipes = sfui.recipes or {}
sfui.recipes.browser = sfui.recipes.browser or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/progress.lua
--  Recipe Catalog Completionist Progress Bar & Breakdown Tooltip
-- ══════════════════════════════════════════════════════════════════════════════

if not sfui.isCamelot then return end

local B = sfui.recipes.browser
local common = sfui.common
local GameTooltip = sfui.common.get_tooltip()

--- Get the active status bar texture configured in config.lua / theme engine
--- @return string texturePath
function B.GetBarTexture()
    if sfui.widgets and sfui.widgets.resolve_statusbar_texture and sfui.config and sfui.config.barTexture then
        return sfui.widgets.resolve_statusbar_texture(sfui.config.barTexture)
    end
    if sfui.widgets and sfui.widgets.get_bar_texture then
        return sfui.widgets.get_bar_texture()
    end
    return (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
end

--- Set status bar texture directly across recipe catalog progress bar
--- @param texturePath string?
function sfui.recipes.SetBarTexture(texturePath)
    local tex = texturePath or B.GetBarTexture()
    if B.ui and B.ui.progressBar and B.ui.progressBar.SetStatusBarTexture then
        B.ui.progressBar:SetStatusBarTexture(tex)
    end
end

--- Create the completionist progress bar frame
--- @param parent Frame
--- @param anchorBelow Frame
--- @return Frame progressBar
function B.CreateProgressBar(parent, anchorBelow)
    local pb = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    B.ui.progressBar = pb
    parent.progressBar = pb
    pb:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -4)
    pb:SetPoint("TOPRIGHT", anchorBelow, "BOTTOMRIGHT", 0, -4)
    pb:SetHeight(12)
    pb:SetStatusBarTexture(B.GetBarTexture())
    pb:SetStatusBarColor(0.15, 0.70, 0.40, 0.90)
    common.apply_flat_backdrop(pb, { 0.06, 0.06, 0.08, 0.85 }, { 0.18, 0.18, 0.22, 0.85 })

    local progressText = pb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("CENTER", pb, "CENTER", 0, 0)
    pb.text = progressText

    return pb
end

--- Update progress bar values and tooltip breakdown
function B.UpdateProgressBar()
    local pb = B.ui.progressBar
    if not pb or not B.selectedSkillID then
        if pb then pb:Hide() end
        return
    end

    pb:SetStatusBarTexture(B.GetBarTexture())

    local candidates = B.GetCandidatesForSkill(B.selectedSkillID)
    local totalCount = #candidates
    if totalCount == 0 then
        pb:Hide()
        return
    end

    pb:Show()
    local knownCount = 0
    local knownTrainer, totalTrainer = 0, 0
    local knownVendor, totalVendor = 0, 0
    local knownQuest, totalQuest = 0, 0
    local knownDrop, totalDrop = 0, 0
    local knownRep, totalRep = 0, 0
    local knownLimited, totalLimited = 0, 0
    local knownEvent, totalEvent = 0, 0

    for _, r in ipairs(candidates) do
        local isKnown = B.IsRecipeLearned(r.id, r)
        if isKnown then
            knownCount = knownCount + 1
        end

        local isTr = B.RecipeMatchesSource(r, "trainer")
        if isTr then
            totalTrainer = totalTrainer + 1
            if isKnown then knownTrainer = knownTrainer + 1 end
        end

        local isVn = B.RecipeMatchesSource(r, "vendor")
        if isVn then
            totalVendor = totalVendor + 1
            if isKnown then knownVendor = knownVendor + 1 end
        end

        local isQst = B.RecipeMatchesSource(r, "quest")
        if isQst then
            totalQuest = totalQuest + 1
            if isKnown then knownQuest = knownQuest + 1 end
        end

        local isDrp = B.RecipeMatchesSource(r, "drop")
        if isDrp then
            totalDrop = totalDrop + 1
            if isKnown then knownDrop = knownDrop + 1 end
        end

        local isRp = B.RecipeMatchesSource(r, "reputation")
        if isRp then
            totalRep = totalRep + 1
            if isKnown then knownRep = knownRep + 1 end
        end

        local isLim = B.RecipeMatchesSource(r, "limited_stock")
        if isLim then
            totalLimited = totalLimited + 1
            if isKnown then knownLimited = knownLimited + 1 end
        end

        local isEv = (r.isEvent or r.event or (B.EVENT_RECIPES and B.EVENT_RECIPES[r.id] ~= nil))
        if isEv then
            totalEvent = totalEvent + 1
            if isKnown then knownEvent = knownEvent + 1 end
        end
    end

    local pct = totalCount > 0 and (knownCount / totalCount * 100) or 0
    pb:SetMinMaxValues(0, math.max(1, totalCount))
    pb:SetValue(knownCount)

    local profName = "profession"
    for _, p in ipairs(B.playerProfessions) do
        if p.skillID == B.selectedSkillID then
            profName = p.name
            break
        end
    end

    pb.text:SetText(string.format("%s: %d / %d known (%.1f%%)", profName, knownCount, totalCount, pct))

    pb:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(string.format("%s catalog completion", profName), 1, 0.82, 0)
        GameTooltip:AddDoubleLine("total known:", string.format("%d / %d (%.1f%%)", knownCount, totalCount, pct), 1, 1, 1, 0.2, 1, 0.4)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("source breakdown:", 0.8, 0.8, 0.8)

        local function AddBreakdown(label, known, total, r, g, b)
            if total > 0 then
                local p = (known / total) * 100
                GameTooltip:AddDoubleLine("  " .. label .. ":", string.format("%d / %d (%.1f%%)", known, total, p), 0.9, 0.9, 0.9, r, g, b)
            end
        end

        AddBreakdown("trainers", knownTrainer, totalTrainer, 0.4, 0.8, 1)
        AddBreakdown("vendors", knownVendor, totalVendor, 1, 0.82, 0)
        AddBreakdown("quests", knownQuest, totalQuest, 0.2, 1, 0.4)
        AddBreakdown("world drops", knownDrop, totalDrop, 0.7, 0.4, 1)
        AddBreakdown("reputation", knownRep, totalRep, 0.4, 0.7, 1)
        AddBreakdown("limited stock", knownLimited, totalLimited, 1, 0.6, 0.2)
        AddBreakdown("seasonal events", knownEvent, totalEvent, 1, 0.4, 0.7)

        GameTooltip:Show()
    end)

    pb:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end
