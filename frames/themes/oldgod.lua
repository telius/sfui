local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/oldgod.lua
--  Authentic Old Gods Theme Definition (inspired by Chonky Character Sheet)
--  Sculpted blackened void alloy, coiling tentacles, glowing void eye crest,
--  side tentacle pillars, razor-sharp crystal containers, and cosmic nebula.
-- ══════════════════════════════════════════════════════════════════════════════

local OLDGOD_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\oldgod\\"

local function GetOldGodTexture(file)
    return OLDGOD_MEDIA .. file
end

function sfui.theme.IsOldGodBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "oldGodBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.oldGodBackdrop ~= nil then
        return SfuiDB.theme.oldGodBackdrop == true
    end
    return SfuiDB and SfuiDB.themeOldGodBackdrop == true
end

function sfui.theme.SetOldGodBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeOldGodBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.oldGodBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "oldGodBackdrop", enabled and true or false)
    end
end

-- Slice definitions matching Chonky themesdb
local FRAME_SLICES = {
    TL = { tex = "char_frame_border.png", cx = -22, cy = 32,  map = { 95, 95, 0, 0.28, 0, 0.284 } },
    T  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 299, 190, 0.28, 0.72, 0, 0.284 } },
    TR = { tex = "char_frame_border.png", cx = 22,  cy = 32,  map = { 95, 95, 0.72, 1.0, 0, 0.284 } },
    R  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 190, 289, 0.72, 1.0, 0.284, 0.716 } },
    BR = { tex = "char_frame_border.png", cx = 22,  cy = -32, map = { 95, 95, 0.72, 1.0, 0.716, 1.0 } },
    B  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 299, 190, 0.28, 0.72, 0.716, 1.0 } },
    BL = { tex = "char_frame_border.png", cx = -22, cy = -32, map = { 95, 95, 0, 0.28, 0.716, 1.0 } },
    L  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 190, 289, 0, 0.28, 0.284, 0.716 } },
}

local PAPER_SLICES = {
    TL = { tex = "paperdoll_border.png", cx = -10, cy = 6,  map = { 35, 35, 0, 0.15, 0, 0.155 } },
    T  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 328, 70, 0.15, 0.85, 0, 0.155 } },
    TR = { tex = "paperdoll_border.png", cx = 4,   cy = 6,  map = { 35, 35, 0.85, 1.0, 0, 0.155 } },
    R  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 70, 312, 0.85, 1.0, 0.155, 0.845 } },
    BR = { tex = "paperdoll_border.png", cx = 4,   cy = -3, map = { 35, 35, 0.85, 1.0, 0.845, 1.0 } },
    B  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 328, 70, 0.15, 0.85, 0.845, 1.0 } },
    BL = { tex = "paperdoll_border.png", cx = -10, cy = -3, map = { 35, 35, 0, 0.15, 0.845, 1.0 } },
    L  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 70, 312, 0, 0.15, 0.155, 0.845 } },
}

local STATS_SLICES = {
    TL = { tex = "stats_border.png", cx = -3, cy = 0,  map = { 15, 15, 0, 0.118, 0, 0.118 } },
    T  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 290, 45, 0.118, 0.882, 0, 0.118 } },
    TR = { tex = "stats_border.png", cx = 1,  cy = 0,  map = { 15, 15, 0.882, 1.0, 0, 0.118 } },
    R  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 45, 290, 0.882, 1.0, 0.118, 0.882 } },
    BR = { tex = "stats_border.png", cx = 1,  cy = 0,  map = { 15, 15, 0.882, 1.0, 0.882, 1.0 } },
    B  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 290, 45, 0.118, 0.882, 0.882, 1.0 } },
    BL = { tex = "stats_border.png", cx = -3, cy = 0,  map = { 15, 15, 0, 0.118, 0.882, 1.0 } },
    L  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 45, 290, 0, 0.118, 0.118, 0.882 } },
}

local function apply_slice_piece(tex, slice, customPath)
    tex:SetTexture(customPath or GetOldGodTexture(slice.tex))
    tex:SetTexCoord(slice.map[3], slice.map[4], slice.map[5], slice.map[6])
    tex:Show()
    if tex.SetTextureSliceMode then
        tex:SetTextureSliceMode(1)
    end
end

local function update_window_layout(frame)
    local layers = frame.sfuiOldGodLayers
    if not layers or not layers.borderFrame:IsShown() then return end

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 0 or h <= 0 then return end

    local isSmall = (h < 220 or w < 300)
    local s = isSmall and PAPER_SLICES or FRAME_SLICES
    local texPath = GetOldGodTexture(isSmall and "paperdoll_border.png" or "char_frame_border.png")
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

    -- Top Overlay: The Piercing Old God Eye Topper
    if layers.topOverlay then
        if w >= 200 then
            local scale = math.min(1.0, math.max(0.40, (w - 20) / 400))
            layers.topOverlay:SetSize(400 * scale, 80.17 * scale)
            layers.topOverlay:ClearAllPoints()
            layers.topOverlay:SetPoint("CENTER", layers.borderFrame, "TOP", 0, 18 * scale)
            layers.topOverlay:Show()
        else
            layers.topOverlay:Hide()
        end
    end

    -- Left & Right Side Pillars: Coiling Tentacles & Staring Void Eyes
    if layers.leftOverlay and layers.rightOverlay then
        if h >= 360 and w >= 360 and not isSmall then
            local sideH = math.min(428.07, h - 30)
            layers.leftOverlay:SetSize(50, sideH)
            layers.leftOverlay:ClearAllPoints()
            layers.leftOverlay:SetPoint("CENTER", layers.L, "LEFT", 0, 0)
            layers.leftOverlay:Show()

            layers.rightOverlay:SetSize(50, sideH)
            layers.rightOverlay:ClearAllPoints()
            layers.rightOverlay:SetPoint("CENTER", layers.R, "RIGHT", 0, 0)
            layers.rightOverlay:Show()
        else
            layers.leftOverlay:Hide()
            layers.rightOverlay:Hide()
        end
    end

    -- Textured void nebula backdrop (opt-in via tab_theme, defaults to false)
    local useTexturedBackdrop = sfui.theme.IsOldGodBackdropActive and sfui.theme.IsOldGodBackdropActive()
    if layers.bg then
        if useTexturedBackdrop then
            layers.bg:SetTexture(GetOldGodTexture("frame_bg.png"))
            layers.bg:SetAlpha(0.85)
            layers.bg:Show()
        else
            layers.bg:Hide()
        end
    end
end

local oldGodTheme = {
    id             = "oldgod",
    name           = "Old Gods",
    desc           = "authentic chonky old gods theme: sculpted blackened void alloy, curling tentacles, glowing void eye crest, side tentacle pillars, and soft void amethyst.",
    clientTag      = "any",
    barTexture     = "Flat",
    isAvailable    = function()
        return true
    end,
    colors         = {
        id             = "oldgod",
        name           = "Old Gods",
        highlightColor = { 0.56, 0.26, 0.72, 1.0 }, -- Subtle Voidglow Violet (#8F43B7)
        accentColor    = { 0.78, 0.48, 1.00, 1.0 }, -- Luminous Void Indigo / Violet (#C77AFF)
        headerColor    = { 0.92, 0.82, 1.00, 1.0 }, -- Pale Eldritch Violet (#EBD1FF)
        backdropColor  = { 0.05, 0.03, 0.08, 0.94 }, -- Deep Void Black / Abyssal (#0D0814)
        borderColor    = { 0.22, 0.16, 0.30, 1.0 },  -- Soft Void Amethyst (#38294C)
        containerColor = { 0.09, 0.06, 0.14, 0.88 }, -- Blackened Void Alloy Inset (#170F24)
        tabSelected    = { 0.82, 0.52, 1.00, 1.0 },  -- Radiant Void Glow
        tabNormal      = { 0.65, 0.55, 0.78, 1.0 },  -- Muted Amethyst Slate
        dimTextColor   = { 0.50, 0.42, 0.60, 1.0 },  -- Dim Voidshadow Slate (#806B99)
    },
    atlases        = {
        headerBanner        = "Nzoth-tooltip-topper",
        lootCard            = "LootToast-Nzoth",
        corruptedOverlay    = "Nzoth-charactersheet-item-glow",
        eyeIcon             = "Nzoth-charactersheet-icon",
        eyeGlow             = "Nzoth-charactersheet-icon-glow",
    },
    window         = {
        style       = "oldgod_custom",
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
        backdropColor = { 0.06, 0.04, 0.10, 0.85 },
        borderColor   = { 0.28, 0.18, 0.40, 1.0 },
        sparkColor    = { 0.85, 0.45, 1.00, 1.0 },
        castbar       = {
            iconBorderColor = { 0.35, 0.20, 0.50, 1.0 },
            sparkColor      = { 0.85, 0.45, 1.00, 1.0 },
        },
    },
}

-- Custom ApplyWindow implementation using authentic Chonky frame borders
function oldGodTheme.ApplyWindow(frame, options, theme)
    if not frame then return end
    sfui.common.set_pixel_snapping(frame)

    -- Hide conflicting layers from other themes
    if frame.sfuiThemeLayers and frame.sfuiThemeLayers.borderFrame then
        frame.sfuiThemeLayers.borderFrame:Hide()
    end
    if frame.sfuiFallenSanctumLayers and frame.sfuiFallenSanctumLayers.borderFrame then
        frame.sfuiFallenSanctumLayers.borderFrame:Hide()
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

    if not frame.sfuiOldGodLayers then
        local borderFrame = CreateFrame("Frame", nil, frame)
        borderFrame:SetAllPoints(frame)
        borderFrame:SetFrameLevel(math.max(1, (frame:GetFrameLevel() or 1) + 1))
        borderFrame:EnableMouse(false)

        local solidBg = borderFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        solidBg:SetAllPoints(borderFrame)
        solidBg:SetColorTexture(0.05, 0.03, 0.08, 0.98)

        local bg = borderFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", 6, -6)
        bg:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", -6, 6)
        bg:SetTexture(GetOldGodTexture("frame_bg.png"))
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
        topOverlay:SetTexture(GetOldGodTexture("frame_top_img.png"))

        local leftOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        leftOverlay:SetTexture(GetOldGodTexture("frame_left_img.png"))

        local rightOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        rightOverlay:SetTexture(GetOldGodTexture("frame_right_img.png"))

        frame.sfuiOldGodLayers = {
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

    local layers = frame.sfuiOldGodLayers
    layers.borderFrame:Show()
    local pal = sfui.theme.GetPalette()
    layers.solidBg:SetColorTexture(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], pal.backdropColor[4] or 0.94)
    layers.solidBg:Show()

    local useTexturedBackdrop = sfui.theme.IsOldGodBackdropActive and sfui.theme.IsOldGodBackdropActive()
    if useTexturedBackdrop then
        layers.bg:SetTexture(GetOldGodTexture("frame_bg.png"))
        layers.bg:SetAlpha(0.85)
        layers.bg:Show()
    else
        layers.bg:Hide()
    end

    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end

    if not frame._sfuiOldGodResizeHook then
        frame._sfuiOldGodResizeHook = true
        frame:HookScript("OnSizeChanged", function(self)
            if sfui.theme.GetActiveThemeID() == "oldgod" then
                update_window_layout(self)
            end
        end)
    end

    update_window_layout(frame)

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 0 or h <= 0 then
        C_Timer.After(0, function()
            if frame and frame:IsShown() and sfui.theme.GetActiveThemeID() == "oldgod" then
                update_window_layout(frame)
            end
        end)
    end

    frame.isCamelotThemed = false
    sfui.theme.ElevateWindowContents(frame)
end

-- Custom ApplyContainer implementation using authentic Chonky stats/paperdoll borders
function oldGodTheme.ApplyContainer(containerPanel, theme)
    if not containerPanel then return end
    sfui.common.set_pixel_snapping(containerPanel)

    if containerPanel.nineSliceInset then
        if NineSliceUtil and NineSliceUtil.HideLayout then
            NineSliceUtil.HideLayout(containerPanel.nineSliceInset)
        end
        containerPanel.nineSliceInset:Hide()
    end

    if containerPanel.sfuiFallenSanctumContainer and containerPanel.sfuiFallenSanctumContainer.frame then
        containerPanel.sfuiFallenSanctumContainer.frame:Hide()
    end
    if containerPanel.sfuiMawContainer and containerPanel.sfuiMawContainer.frame then
        containerPanel.sfuiMawContainer.frame:Hide()
    end
    if containerPanel.sfuiNecrolordContainer and containerPanel.sfuiNecrolordContainer.frame then
        containerPanel.sfuiNecrolordContainer.frame:Hide()
    end

    if not containerPanel.sfuiOldGodContainer then
        local bFrame = CreateFrame("Frame", nil, containerPanel)
        bFrame:SetAllPoints(containerPanel)
        bFrame:SetFrameLevel(math.max(1, (containerPanel:GetFrameLevel() or 1)))
        bFrame:EnableMouse(false)

        local solid = bFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        solid:SetAllPoints(bFrame)
        solid:SetColorTexture(0.09, 0.06, 0.14, 0.88)

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
        local texPath = GetOldGodTexture("stats_border.png")
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

        containerPanel.sfuiOldGodContainer = {
            frame = bFrame,
            solid = solid,
        }
    end

    local bFrame = containerPanel.sfuiOldGodContainer.frame
    bFrame:SetFrameLevel(math.max(1, (containerPanel:GetFrameLevel() or 1)))
    bFrame:Show()
    if containerPanel.SetBackdrop then
        containerPanel:SetBackdrop(nil)
    end
end

-- Custom ApplyHeader implementation using authentic Chonky void header banner
function oldGodTheme.ApplyHeader(header, theme)
    if not header then return end
    local pal = sfui.theme.GetPalette()

    if not header.sfuiOldGodHeader then
        local bg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetAllPoints(header)
        bg:SetTexture(GetOldGodTexture("stats_header.png"))
        header.sfuiOldGodHeader = bg
    end

    header.sfuiOldGodHeader:Show()
    if header.sfuiFallenSanctumHeader then header.sfuiFallenSanctumHeader:Hide() end
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

sfui.theme.RegisterTheme(oldGodTheme)

-- Register alias for "oldgods" so both singular and plural forms resolve seamlessly
local regThemes, _ = sfui.theme.GetRegisteredThemes()
if regThemes then
    regThemes["oldgods"] = oldGodTheme
    if sfui.theme.palettes then
        sfui.theme.palettes["oldgods"] = oldGodTheme.colors
    end
end
