local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/fallensanctum.lua
--  Authentic Fallen Sanctum Theme Definition (inspired by Chonky Character Sheet)
--  Sculpted Torghast domination crypt stone, horned gargoyle skull crest,
--  hanging soul chains, blood crimson crypt iron, and soul-fire teal (#1df2c6).
-- ══════════════════════════════════════════════════════════════════════════════

local FALLENSANCTUM_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\fallensanctum\\"

local function GetFallenSanctumTexture(file)
    return FALLENSANCTUM_MEDIA .. file
end

function sfui.theme.IsFallenSanctumBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "fallenSanctumBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.fallenSanctumBackdrop ~= nil then
        return SfuiDB.theme.fallenSanctumBackdrop == true
    end
    return SfuiDB and SfuiDB.themeFallenSanctumBackdrop == true
end

function sfui.theme.SetFallenSanctumBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeFallenSanctumBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.fallenSanctumBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "fallenSanctumBackdrop", enabled and true or false)
    end
end

-- Slice definitions matching Chonky themesdb
local FRAME_SLICES = {
    TL = { tex = "char_frame_border.png", cx = -17, cy = 25,  map = { 68, 68, 0, 0.229, 0, 0.232 } },
    T  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 379, 160, 0.229, 0.771, 0, 0.232 } },
    TR = { tex = "char_frame_border.png", cx = 17,  cy = 25,  map = { 160, 160, 0.771, 1.0, 0, 0.232 } },
    R  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 160, 371, 0.771, 1.0, 0.232, 0.768 } },
    BR = { tex = "char_frame_border.png", cx = 17,  cy = -25, map = { 160, 160, 0.771, 1.0, 0.768, 1.0 } },
    B  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 379, 160, 0.229, 0.771, 0.768, 1.0 } },
    BL = { tex = "char_frame_border.png", cx = -17, cy = -25, map = { 160, 160, 0, 0.229, 0.768, 1.0 } },
    L  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 160, 371, 0, 0.229, 0.232, 0.768 } },
}

local PAPER_SLICES = {
    TL = { tex = "paperdoll_border.png", cx = -7, cy = 3,  map = { 20, 20, 0, 0.139, 0, 0.144 } },
    T  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 339, 65, 0.139, 0.861, 0, 0.144 } },
    TR = { tex = "paperdoll_border.png", cx = 4,  cy = 3,  map = { 65, 65, 0.861, 1.0, 0, 0.144 } },
    R  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 65, 322, 0.861, 1.0, 0.144, 0.856 } },
    BR = { tex = "paperdoll_border.png", cx = 4,  cy = -3, map = { 65, 65, 0.861, 1.0, 0.856, 1.0 } },
    B  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 339, 65, 0.139, 0.861, 0.856, 1.0 } },
    BL = { tex = "paperdoll_border.png", cx = -7, cy = -3, map = { 65, 65, 0, 0.139, 0.856, 1.0 } },
    L  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 65, 322, 0, 0.139, 0.144, 0.856 } },
}

local STATS_SLICES = {
    TL = { tex = "stats_border.png", cx = -3, cy = 0, map = { 15, 15, 0, 0.119, 0, 0.118 } },
    T  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 288, 45, 0.119, 0.881, 0, 0.118 } },
    TR = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 45, 0.881, 1.0, 0, 0.118 } },
    R  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 291, 0.881, 1.0, 0.118, 0.882 } },
    BR = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 45, 0.881, 1.0, 0.882, 1.0 } },
    B  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 288, 45, 0.119, 0.881, 0.882, 1.0 } },
    BL = { tex = "stats_border.png", cx = -3, cy = 0, map = { 45, 45, 0, 0.119, 0.882, 1.0 } },
    L  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 291, 0.119, 0.118, 0.882 } },
}

local function apply_slice_piece(tex, slice, customPath)
    tex:SetTexture(customPath or GetFallenSanctumTexture(slice.tex))
    tex:SetTexCoord(slice.map[3], slice.map[4], slice.map[5], slice.map[6])
    tex:Show()
    if tex.SetTextureSliceMode then
        tex:SetTextureSliceMode(1)
    end
end

local function update_window_layout(frame)
    local layers = frame.sfuiFallenSanctumLayers
    if not layers or not layers.borderFrame:IsShown() then return end

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 0 or h <= 0 then return end

    local isSmall = (h < 220 or w < 300)
    local s = isSmall and PAPER_SLICES or FRAME_SLICES
    local texPath = GetFallenSanctumTexture(isSmall and "paperdoll_border.png" or "char_frame_border.png")
    local cornerW = s.TL.map[1]
    local cornerH = s.TL.map[2]

    apply_slice_piece(layers.TL, s.TL, texPath)
    apply_slice_piece(layers.TR, s.TR, texPath)
    apply_slice_piece(layers.BL, s.BL, texPath)
    apply_slice_piece(layers.BR, s.BR, texPath)
    apply_slice_piece(layers.T,  s.T,  texPath)
    apply_slice_piece(layers.B,  s.B,  texPath)
    apply_slice_piece(layers.L,  s.L,  texPath)
    apply_slice_piece(layers.R,  s.R,  texPath)

    layers.TL:ClearAllPoints()
    layers.TL:SetPoint("TOPLEFT", layers.borderFrame, "TOPLEFT", s.TL.cx, s.TL.cy)
    layers.TL:SetSize(cornerW, cornerH)

    layers.TR:ClearAllPoints()
    layers.TR:SetPoint("TOPRIGHT", layers.borderFrame, "TOPRIGHT", s.TR.cx, s.TR.cy)
    layers.TR:SetSize(cornerW, cornerH)

    layers.BL:ClearAllPoints()
    layers.BL:SetPoint("BOTTOMLEFT", layers.borderFrame, "BOTTOMLEFT", s.BL.cx, s.BL.cy)
    layers.BL:SetSize(cornerW, cornerH)

    layers.BR:ClearAllPoints()
    layers.BR:SetPoint("BOTTOMRIGHT", layers.borderFrame, "BOTTOMRIGHT", s.BR.cx, s.BR.cy)
    layers.BR:SetSize(cornerW, cornerH)

    layers.T:ClearAllPoints()
    layers.T:SetPoint("TOPLEFT", layers.TL, "TOPRIGHT", 0, 0)
    layers.T:SetPoint("TOPRIGHT", layers.TR, "TOPLEFT", 0, 0)
    layers.T:SetHeight(cornerH)

    layers.B:ClearAllPoints()
    layers.B:SetPoint("BOTTOMLEFT", layers.BL, "BOTTOMRIGHT", 0, 0)
    layers.B:SetPoint("BOTTOMRIGHT", layers.BR, "BOTTOMLEFT", 0, 0)
    layers.B:SetHeight(cornerH)

    layers.L:ClearAllPoints()
    layers.L:SetPoint("TOPLEFT", layers.TL, "BOTTOMLEFT", 0, 0)
    layers.L:SetPoint("BOTTOMLEFT", layers.BL, "TOPLEFT", 0, 0)
    layers.L:SetWidth(cornerW)

    layers.R:ClearAllPoints()
    layers.R:SetPoint("TOPRIGHT", layers.TR, "BOTTOMRIGHT", 0, 0)
    layers.R:SetPoint("BOTTOMRIGHT", layers.BR, "TOPRIGHT", 0, 0)
    layers.R:SetWidth(cornerW)

    -- Top Overlay: The Horned Gargoyle Skull Crest Topper
    if layers.topOverlay then
        if w >= 200 then
            local scale = math.min(1.0, math.max(0.40, (w - 20) / 410))
            layers.topOverlay:SetSize(410 * scale, 82 * scale)
            layers.topOverlay:ClearAllPoints()
            layers.topOverlay:SetPoint("CENTER", layers.borderFrame, "TOP", 0, 23 * scale)
            layers.topOverlay:Show()
        else
            layers.topOverlay:Hide()
        end
    end

    -- Left & Right Side Pillars: Hanging Soul Chains
    if layers.leftOverlay and layers.rightOverlay then
        if h >= 360 and w >= 360 and not isSmall then
            local sideH = math.min(403, h - 30)
            local scale = sideH / 403
            local sideW = 72 * scale
            layers.leftOverlay:SetSize(sideW, sideH)
            layers.leftOverlay:ClearAllPoints()
            layers.leftOverlay:SetPoint("CENTER", layers.L, "LEFT", -8 * scale, 0)
            layers.leftOverlay:Show()

            layers.rightOverlay:SetSize(sideW, sideH)
            layers.rightOverlay:ClearAllPoints()
            layers.rightOverlay:SetPoint("CENTER", layers.R, "RIGHT", 8 * scale, 0)
            layers.rightOverlay:Show()
        else
            layers.leftOverlay:Hide()
            layers.rightOverlay:Hide()
        end
    end

    -- Textured crypt backdrop (opt-in via tab_theme, defaults to false)
    local useTexturedBackdrop = sfui.theme.IsFallenSanctumBackdropActive and sfui.theme.IsFallenSanctumBackdropActive()
    if layers.bg then
        if useTexturedBackdrop then
            layers.bg:SetTexture(GetFallenSanctumTexture("frame_bg.png"))
            layers.bg:SetAlpha(0.88)
            layers.bg:Show()
        else
            layers.bg:Hide()
        end
    end
end

local fallenSanctumTheme = {
    id             = "fallensanctum",
    name           = "Fallen Sanctum",
    desc           = "bespoke torghast crypt stone: horned gargoyle crest, hanging soul chains, blood crimson crypt iron, and soul-fire teal.",
    clientTag      = "any",
    barTexture     = "Flat",
    isAvailable    = function()
        return true
    end,
    colors         = {
        id             = "fallensanctum",
        name           = "Fallen Sanctum",
        highlightColor = { 0.67, 0.20, 0.17, 1.0 }, -- Blood Crimson (#AB332B)
        accentColor    = { 0.114, 0.949, 0.776, 1.0 }, -- Soul-Fire Teal (#1DF2C6)
        headerColor    = { 0.96, 0.78, 0.78, 1.0 }, -- Pale Crypt Ivory (#F5C7C7)
        backdropColor  = { 0.05, 0.03, 0.04, 0.95 }, -- Deep Charred Crypt Stone
        borderColor    = { 0.47, 0.11, 0.11, 1.0 },  -- Blood Crimson Crypt Iron (#791B1D)
        containerColor = { 0.12, 0.04, 0.05, 0.88 }, -- Crimson-Shadowed Inset
        tabSelected    = { 0.95, 0.25, 0.25, 1.0 },  -- Blazing Crimson Red
        tabNormal      = { 0.78, 0.60, 0.60, 1.0 },  -- Crypt Ash Slate
        dimTextColor   = { 0.55, 0.42, 0.42, 1.0 },  -- Dim Charred Crypt Stone
    },
    atlases        = {
        headerBanner        = "Maw-tooltip-topper",
        lootCard            = "LootToast-Maw",
        corruptedOverlay    = nil,
    },
    window         = {
        style       = "fallensanctum_custom",
    },
    header         = {
        style       = "accent_bar",
        height      = 24,
    },
    closeButton    = {
        style       = "flat_cross",
    },
    lootfeed       = {
        style       = "minimal_flat",
    },
    bars           = {
        style         = "thin",
        texture       = "Flat",
        backdropColor = { 0.06, 0.03, 0.04, 0.85 },
        borderColor   = { 0.45, 0.12, 0.12, 1.0 },
        sparkColor    = { 0.114, 0.949, 0.776, 1.0 },
        castbar       = {
            iconBorderColor = { 0.55, 0.15, 0.15, 1.0 },
            sparkColor      = { 0.114, 0.949, 0.776, 1.0 },
        },
    },
}

-- Custom ApplyWindow implementation using authentic Chonky frame borders
function fallenSanctumTheme.ApplyWindow(frame, options, theme)
    if not frame then return end
    sfui.common.set_pixel_snapping(frame)

    -- Hide conflicting layers from other themes
    if frame.sfuiThemeLayers and frame.sfuiThemeLayers.borderFrame then
        frame.sfuiThemeLayers.borderFrame:Hide()
    end
    if frame.sfuiOldGodLayers and frame.sfuiOldGodLayers.borderFrame then
        frame.sfuiOldGodLayers.borderFrame:Hide()
    end
    if frame.sfuiMawLayers and frame.sfuiMawLayers.borderFrame then
        frame.sfuiMawLayers.borderFrame:Hide()
    end
    if frame.sfuiNecrolordLayers and frame.sfuiNecrolordLayers.borderFrame then
        frame.sfuiNecrolordLayers.borderFrame:Hide()
    end
    if frame.sfuiNineSlices then
        for _, c in pairs(frame.sfuiNineSlices) do c:Hide() end
    end
    frame.sfuiActiveNineSlice = nil

    if not frame.sfuiFallenSanctumLayers then
        local borderFrame = CreateFrame("Frame", nil, frame)
        borderFrame:SetAllPoints(frame)
        borderFrame:SetFrameLevel(math.max(1, (frame:GetFrameLevel() or 1) + 1))
        borderFrame:EnableMouse(false)

        local solidBg = borderFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints(borderFrame)
        solidBg:SetColorTexture(0.05, 0.03, 0.04, 0.98)

        local bg = borderFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 6, -6)
        bg:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", -6, 6)
        bg:SetTexture(GetFallenSanctumTexture("frame_bg.png"))
        bg:SetAlpha(0.92)

        local function makePiece(layer, sub)
            return borderFrame:CreateTexture(nil, layer, nil, sub)
        end

        local TL = makePiece("BORDER", 1)
        local TR = makePiece("BORDER", 1)
        local BL = makePiece("BORDER", 1)
        local BR = makePiece("BORDER", 1)
        local T  = makePiece("BORDER", 1)
        local B  = makePiece("BORDER", 1)
        local L  = makePiece("BORDER", 1)
        local R  = makePiece("BORDER", 1)

        local topOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        topOverlay:SetTexture(GetFallenSanctumTexture("frame_top_img.png"))

        local leftOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        leftOverlay:SetTexture(GetFallenSanctumTexture("frame_left_img.png"))

        local rightOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        rightOverlay:SetTexture(GetFallenSanctumTexture("frame_right_img.png"))

        frame.sfuiFallenSanctumLayers = {
            borderFrame  = borderFrame,
            solidBg      = solidBg,
            bg           = bg,
            TL = TL, TR = TR, BL = BL, BR = BR,
            T = T, B = B, L = L, R = R,
            topOverlay   = topOverlay,
            leftOverlay  = leftOverlay,
            rightOverlay = rightOverlay,
        }
    end

    local layers = frame.sfuiFallenSanctumLayers
    layers.borderFrame:Show()
    local pal = sfui.theme.GetPalette()
    layers.solidBg:SetColorTexture(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], pal.backdropColor[4] or 0.95)
    layers.solidBg:Show()

    local useTexturedBackdrop = sfui.theme.IsFallenSanctumBackdropActive and sfui.theme.IsFallenSanctumBackdropActive()
    if useTexturedBackdrop then
        layers.bg:SetTexture(GetFallenSanctumTexture("frame_bg.png"))
        layers.bg:SetAlpha(0.88)
        layers.bg:Show()
    else
        layers.bg:Hide()
    end

    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end

    if not frame._sfuiFallenSanctumResizeHook then
        frame._sfuiFallenSanctumResizeHook = true
        frame:HookScript("OnSizeChanged", function(self)
            if sfui.theme.GetActiveThemeID() == "fallensanctum" then
                update_window_layout(self)
            end
        end)
    end

    update_window_layout(frame)

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 0 or h <= 0 then
        C_Timer.After(0, function()
            if frame and frame:IsShown() and sfui.theme.GetActiveThemeID() == "fallensanctum" then
                update_window_layout(frame)
            end
        end)
    end

    frame.isCamelotThemed = false
    sfui.theme.ElevateWindowContents(frame)
end

-- Custom ApplyContainer implementation using authentic Chonky stats/paperdoll borders
function fallenSanctumTheme.ApplyContainer(containerPanel, theme)
    if not containerPanel then return end
    sfui.common.set_pixel_snapping(containerPanel)

    if containerPanel.nineSliceInset then
        if NineSliceUtil and NineSliceUtil.HideLayout then
            NineSliceUtil.HideLayout(containerPanel.nineSliceInset)
        end
        containerPanel.nineSliceInset:Hide()
    end

    if containerPanel.sfuiOldGodContainer and containerPanel.sfuiOldGodContainer.frame then
        containerPanel.sfuiOldGodContainer.frame:Hide()
    end
    if containerPanel.sfuiMawContainer and containerPanel.sfuiMawContainer.frame then
        containerPanel.sfuiMawContainer.frame:Hide()
    end
    if containerPanel.sfuiNecrolordContainer and containerPanel.sfuiNecrolordContainer.frame then
        containerPanel.sfuiNecrolordContainer.frame:Hide()
    end

    if not containerPanel.sfuiFallenSanctumContainer then
        local bFrame = CreateFrame("Frame", nil, containerPanel)
        bFrame:SetAllPoints(containerPanel)
        bFrame:SetFrameLevel(math.max(1, (containerPanel:GetFrameLevel() or 1) + 1))
        bFrame:EnableMouse(false)

        local solid = bFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        solid:SetAllPoints(bFrame)
        solid:SetColorTexture(0.12, 0.04, 0.05, 0.88)

        local function makePiece(sub)
            return bFrame:CreateTexture(nil, "BORDER", nil, sub)
        end

        local TL = makePiece(1)
        local TR = makePiece(1)
        local BL = makePiece(1)
        local BR = makePiece(1)
        local T  = makePiece(1)
        local B  = makePiece(1)
        local L  = makePiece(1)
        local R  = makePiece(1)

        local s = STATS_SLICES
        local texPath = GetFallenSanctumTexture("stats_border.png")
        apply_slice_piece(TL, s.TL, texPath)
        apply_slice_piece(TR, s.TR, texPath)
        apply_slice_piece(BL, s.BL, texPath)
        apply_slice_piece(BR, s.BR, texPath)
        apply_slice_piece(T,  s.T,  texPath)
        apply_slice_piece(B,  s.B,  texPath)
        apply_slice_piece(L,  s.L,  texPath)
        apply_slice_piece(R,  s.R,  texPath)

        TL:SetPoint("TOPLEFT", bFrame, "TOPLEFT", s.TL.cx, s.TL.cy)
        TL:SetSize(15, 15)

        TR:SetPoint("TOPRIGHT", bFrame, "TOPRIGHT", s.TR.cx, s.TR.cy)
        TR:SetSize(15, 15)

        BL:SetPoint("BOTTOMLEFT", bFrame, "BOTTOMLEFT", s.BL.cx, s.BL.cy)
        BL:SetSize(15, 15)

        BR:SetPoint("BOTTOMRIGHT", bFrame, "BOTTOMRIGHT", s.BR.cx, s.BR.cy)
        BR:SetSize(15, 15)

        T:SetPoint("TOPLEFT", TL, "TOPRIGHT", 0, 0)
        T:SetPoint("TOPRIGHT", TR, "TOPLEFT", 0, 0)
        T:SetHeight(15)

        B:SetPoint("BOTTOMLEFT", BL, "BOTTOMRIGHT", 0, 0)
        B:SetPoint("BOTTOMRIGHT", BR, "BOTTOMLEFT", 0, 0)
        B:SetHeight(15)

        L:SetPoint("TOPLEFT", TL, "BOTTOMLEFT", 0, 0)
        L:SetPoint("BOTTOMLEFT", BL, "TOPLEFT", 0, 0)
        L:SetWidth(15)

        R:SetPoint("TOPRIGHT", TR, "BOTTOMRIGHT", 0, 0)
        R:SetPoint("BOTTOMRIGHT", BR, "TOPRIGHT", 0, 0)
        R:SetWidth(15)

        containerPanel.sfuiFallenSanctumContainer = {
            frame = bFrame,
            solid = solid,
        }
    end

    local bFrame = containerPanel.sfuiFallenSanctumContainer.frame
    bFrame:SetFrameLevel(math.max(1, (containerPanel:GetFrameLevel() or 1) + 1))
    bFrame:Show()
    if containerPanel.SetBackdrop then
        containerPanel:SetBackdrop(nil)
    end
end

-- Custom ApplyHeader implementation using authentic Chonky crypt stats header
function fallenSanctumTheme.ApplyHeader(header, theme)
    if not header then return end
    local pal = sfui.theme.GetPalette()

    if not header.sfuiFallenSanctumHeader then
        local bg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetAllPoints(header)
        bg:SetTexture(GetFallenSanctumTexture("stats_header.png"))
        header.sfuiFallenSanctumHeader = bg
    end

    header.sfuiFallenSanctumHeader:Show()
    if header.sfuiOldGodHeader then header.sfuiOldGodHeader:Hide() end
    if header.sfuiMawHeader then header.sfuiMawHeader:Hide() end
    if header.sfuiNecrolordHeader then header.sfuiNecrolordHeader:Hide() end
    if header.bgBanner then header.bgBanner:Hide() end
    if header.accent then header.accent:Hide() end
    if header.SetBackdrop then header:SetBackdrop(nil) end

    header:SetHeight(24)
    if header.title then
        header.title:ClearAllPoints()
        header.title:SetPoint("CENTER", header, "CENTER", 0, 0)
        header.title:SetJustifyH("CENTER")
        header.title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
    end
    if header.count then
        header.count:ClearAllPoints()
        header.count:SetPoint("RIGHT", header, "RIGHT", -12, 0)
        header.count:SetJustifyH("RIGHT")
        header.count:SetTextColor(pal.dimTextColor[1], pal.dimTextColor[2], pal.dimTextColor[3], 1)
    end
end

sfui.theme.RegisterTheme(fallenSanctumTheme)

-- Register aliases for "sanctum" and "torghast"
local regThemes, _ = sfui.theme.GetRegisteredThemes()
if regThemes then
    regThemes["sanctum"] = fallenSanctumTheme
    regThemes["torghast"] = fallenSanctumTheme
    if sfui.theme.palettes then
        sfui.theme.palettes["sanctum"] = fallenSanctumTheme.colors
        sfui.theme.palettes["torghast"] = fallenSanctumTheme.colors
    end
end
