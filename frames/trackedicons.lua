local addonName, addon = ...
sfui.trackedicons = {}

local panels = {} -- Active icon panels

-- Helper to update icon state (visibility, cooldown, charges)
local function UpdateIconState(icon)
    if not icon.id or not icon.entry then return false end

    local isSecret = false
    if icon.entry and icon.entry.settings then
        if icon.entry.settings.issecretvalue ~= nil then
            isSecret = icon.entry.settings.issecretvalue
        elseif icon.entry.settings.issecret ~= nil then
            isSecret = icon.entry.settings.issecret
        end
    end

    local isVisible = true
    if isSecret and not sfui.trackedicons.unlockMode then
        isVisible = false
    end

    if isVisible then
        icon:Show()
        -- Update textures/cooldowns here if needed
        -- For now, we assume simple visibility for the editor/anchor test
    else
        icon:Hide()
    end

    return isVisible
end

-- Create a single icon frame
local function CreateIconFrame(parent, id, entry)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 40)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local iconTexture
    if entry.type == "item" then
        iconTexture = C_Item.GetItemIconByID(id)
    else
        iconTexture = C_Spell.GetSpellTexture(id)
    end
    tex:SetTexture(iconTexture or 134400) -- Default question mark

    f.id = id
    f.entry = entry

    return f
end

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig)
    if not panelFrame or not panelConfig then return end

    local size = panelConfig.size or 40
    local spacing = panelConfig.spacing or 5

    -- Ensure panel position is updated from Config with Dynamic Anchoring
    panelFrame:ClearAllPoints()
    local isLeft = (panelConfig.x or 0) < 0
    local anchor = isLeft and "TOPRIGHT" or "TOPLEFT"

    panelFrame:SetPoint(anchor, UIParent, "BOTTOM", panelConfig.x or 0, panelConfig.y or 0)

    -- Hide all known icons first (full redraw of state)
    if panelFrame.icons then
        for _, icon in pairs(panelFrame.icons) do icon:Hide() end
    else
        panelFrame.icons = {}
    end

    local activeIcons = {}
    local entries = panelConfig.entries or {}

    for i, entry in ipairs(entries) do
        local id = entry.id
        if id then
            if not panelFrame.icons[i] then
                panelFrame.icons[i] = CreateIconFrame(panelFrame, id, entry)
            end

            local icon = panelFrame.icons[i]
            if icon then
                icon.id = id
                icon.type = entry.type
                icon.entry = entry

                local isVisibleValue = UpdateIconState(icon)
                if isVisibleValue then
                    table.insert(activeIcons, icon)
                end
            end
        end
    end

    -- Layout Active Icons
    local numColumns = panelConfig.columns or #activeIcons
    if numColumns < 1 then numColumns = 1 end

    local maxWidth, maxHeight = 0, 0

    for i, icon in ipairs(activeIcons) do
        icon:ClearAllPoints()
        icon:SetSize(size, size)

        local col = (i - 1) % numColumns
        local row = math.floor((i - 1) / numColumns)

        local x = col * (size + spacing)
        local y = -row * (size + spacing)

        if isLeft then
            icon:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -x, y)
        else
            icon:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", x, y)
        end

        maxWidth = math.max(maxWidth, (col + 1) * (size + spacing) - spacing)
        maxHeight = math.max(maxHeight, (row + 1) * (size + spacing) - spacing)
    end

    panelFrame:SetSize(math.max(maxWidth, 1), math.max(maxHeight, 1))
end

function sfui.trackedicons.Update()
    -- DB Migration / Initialization
    if not SfuiDB.cooldownPanels then
        SfuiDB.cooldownPanels = {}

        local leftEntries = {}

        -- Migrate legacy trackedIcons if present
        if SfuiDB.trackedIcons then
            for id, cfg in pairs(SfuiDB.trackedIcons) do
                if type(id) == "number" then
                    table.insert(leftEntries, { id = id, settings = cfg })
                end
            end
            SfuiDB.trackedIcons = nil -- Clear old
        end

        -- Default Left Panel
        table.insert(SfuiDB.cooldownPanels, {
            name = "Left Panel",
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            x = -300,
            y = 300,
            size = 40,
            spacing = 5,
            enabled = true,
            entries = leftEntries -- Put migrated icons here
        })

        -- Default Right Panel
        table.insert(SfuiDB.cooldownPanels, {
            name = "Right Panel",
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            x = 300,
            y = 300,
            size = 40,
            spacing = 5,
            enabled = true,
            entries = {}
        })
    end

    if not SfuiDB or not SfuiDB.cooldownPanels then return end

    -- Render Panels
    for i, panelConfig in ipairs(SfuiDB.cooldownPanels) do
        if panelConfig.enabled then
            if not panels[i] then
                panels[i] = CreateFrame("Frame", "SfuiIconPanel_" .. i, UIParent)
            end
            sfui.trackedicons.UpdatePanelLayout(panels[i], panelConfig)
        elseif panels[i] then
            panels[i]:Hide()
        end
    end
end

function sfui.trackedicons.initialize()
    sfui.common.ensure_tracked_icon_db()

    -- Event handling
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:SetScript("OnEvent", function()
        sfui.trackedicons.Update()
    end)

    sfui.trackedicons.Update()
end
