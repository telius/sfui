local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/maw.lua
--  Authentic Maw & Torghast Spire Theme Definition
--  Bespoke sculpted saronite/obsidian Maw stone, horned domination crown crest,
--  frost-rimmed soul-chains, icy soul-chill blue anima (#65e6f2), and dark soul-slate.
-- ══════════════════════════════════════════════════════════════════════════════

local MAW_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\maw\\"

local function GetMawTexture(file)
    return MAW_MEDIA .. file
end

function sfui.theme.IsMawBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "mawBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.mawBackdrop ~= nil then
        return SfuiDB.theme.mawBackdrop == true
    end
    return SfuiDB and SfuiDB.themeMawBackdrop == true
end

function sfui.theme.SetMawBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeMawBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.mawBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "mawBackdrop", enabled and true or false)
    end
end

-- Slices matching sculpted high-definition border suite
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
    tex:SetTexture(customPath or GetMawTexture(slice.tex))
    tex:SetTexCoord(slice.map[3], slice.map[4], slice.map[5], slice.map[6])
    tex:Show()
    if tex.SetTextureSliceMode then
        tex:SetTextureSliceMode(1)
    end
end

local function update_window_layout(frame)
    local layers = frame.sfuiMawLayers
    if not layers or not layers.borderFrame:IsShown() then return end

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    if w <= 0 or h <= 0 then return end

    local isSmall = (h < 220 or w < 300)
    local s = isSmall and PAPER_SLICES or FRAME_SLICES
    local texPath = GetMawTexture(isSmall and "paperdoll_border.png" or "char_frame_border.png")
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

    -- Top Overlay: The Spiked Maw Domination Crown Crest Topper
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

    -- Side Overlays: Frost-Rimmed Maw Soul Chains
    if layers.leftOverlay and layers.rightOverlay then
        if h >= 260 and w >= 260 then
            local scaleH = math.min(1.0, math.max(0.40, (h - 40) / 403))
            layers.leftOverlay:SetSize(72 * scaleH, 403 * scaleH)
            layers.leftOverlay:ClearAllPoints()
            layers.leftOverlay:SetPoint("CENTER", layers.borderFrame, "LEFT", -8 * scaleH, 0)
            layers.leftOverlay:Show()

            layers.rightOverlay:SetSize(72 * scaleH, 403 * scaleH)
            layers.rightOverlay:ClearAllPoints()
            layers.rightOverlay:SetPoint("CENTER", layers.borderFrame, "RIGHT", 8 * scaleH, 0)
            layers.rightOverlay:Show()
        else
            layers.leftOverlay:Hide()
            layers.rightOverlay:Hide()
        end
    end

    -- Backdrop: Ethereal Soul-Chill Fog
    if layers.backdropTex then
        if sfui.theme.IsMawBackdropActive() then
            layers.backdropTex:Show()
        else
            layers.backdropTex:Hide()
        end
    end
end

local mawTheme = {
    id   = "maw",
    name = "maw",
    desc = "jagged saronite maw spikes, soul-chill blue anima glow (#65e6f2), domination crown crest, and dark soul-slate.",
    clientTag = "any",
    isAvailable = function()
        return true
    end,
    colors = {
        id             = "maw",
        name           = "maw",
        highlightColor = { 0.30, 0.55, 0.70, 1.0 },
        accentColor    = { 0.40, 0.90, 0.95, 1.0 }, -- #65e6f2 soul-chill blue
        headerColor    = { 0.85, 0.95, 1.00, 1.0 },
        backdropColor  = { 0.04, 0.05, 0.07, 0.95 },
        borderColor    = { 0.20, 0.32, 0.40, 1.0 },
        containerColor = { 0.06, 0.08, 0.11, 0.85 },
        tabNormal      = { 0.70, 0.80, 0.85, 1.0 },
        tabSelected    = { 0.40, 0.90, 0.95, 1.0 },
        dimTextColor   = { 0.45, 0.55, 0.62, 1.0 },
    },
    window = {
        style = "bespoke_maw",
    },
    header = {
        style  = "accent_bar",
        height = 24,
    },
    closeButton = {
        style = "flat_cross",
    },
    lootfeed = {
        style = "minimal_flat",
    },
    bars = {
        style      = "thin",
        texture    = "Flat",
        sparkColor = { 0.40, 0.90, 0.95, 1.0 },
        castbar    = {
            sparkColor = { 0.40, 0.90, 0.95, 1.0 },
        },
    },
}

-- Custom ApplyWindow implementation with 8-slice borders and signature Maw toppers
function mawTheme.ApplyWindow(frame, options, theme)
    if not frame then return end
    options = options or {}
    local pal = sfui.theme.GetPalette()

    -- Hide other theme layers if present
    if frame.sfuiOldGodLayers and frame.sfuiOldGodLayers.borderFrame then
        frame.sfuiOldGodLayers.borderFrame:Hide()
    end
    if frame.sfuiFallenSanctumLayers and frame.sfuiFallenSanctumLayers.borderFrame then
        frame.sfuiFallenSanctumLayers.borderFrame:Hide()
    end
    if frame.sfuiNecrolordLayers and frame.sfuiNecrolordLayers.borderFrame then
        frame.sfuiNecrolordLayers.borderFrame:Hide()
    end

    local layers = frame.sfuiMawLayers
    if not layers then
        local borderFrame = CreateFrame("Frame", nil, frame)
        borderFrame:SetAllPoints(frame)
        borderFrame:SetFrameLevel(math.max(1, frame:GetFrameLevel() + 2))

        local function makePiece(subLevel, drawLayer)
            local tex = borderFrame:CreateTexture(nil, drawLayer or "BORDER", nil, subLevel or 1)
            return tex
        end

        local solid = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        solid:SetAllPoints(frame)
        solid:SetColorTexture(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], 0.95)

        local backdropTex = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        backdropTex:SetAllPoints(frame)
        backdropTex:SetTexture(GetMawTexture("frame_bg.png"))
        backdropTex:SetTexCoord(0, 1, 0, 1)

        local topOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        topOverlay:SetTexture(GetMawTexture("frame_top_img.png"))

        local leftOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 5)
        leftOverlay:SetTexture(GetMawTexture("frame_left_img.png"))

        local rightOverlay = borderFrame:CreateTexture(nil, "OVERLAY", nil, 5)
        rightOverlay:SetTexture(GetMawTexture("frame_right_img.png"))

        layers = {
            borderFrame  = borderFrame,
            solid        = solid,
            backdropTex  = backdropTex,
            TL           = makePiece(1),
            TR           = makePiece(1),
            BL           = makePiece(1),
            BR           = makePiece(1),
            T            = makePiece(1),
            B            = makePiece(1),
            L            = makePiece(1),
            R            = makePiece(1),
            topOverlay   = topOverlay,
            leftOverlay  = leftOverlay,
            rightOverlay = rightOverlay,
        }
        frame.sfuiMawLayers = layers

        frame:HookScript("OnSizeChanged", function(self)
            if sfui.theme.GetActiveThemeID() == "maw" then
                update_window_layout(self)
            end
        end)
    end

    layers.borderFrame:Show()
    layers.solid:SetColorTexture(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], 0.95)
    layers.solid:Show()

    if sfui.theme.IsMawBackdropActive() then
        layers.backdropTex:Show()
    else
        layers.backdropTex:Hide()
    end

    if frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end

    update_window_layout(frame)
end

-- Custom ApplyContainer implementation with authentic Maw stats border
function mawTheme.ApplyContainer(containerPanel, theme)
    if not containerPanel then return end
    local pal = sfui.theme.GetPalette()

    -- Hide other theme containers
    if containerPanel.sfuiOldGodContainer and containerPanel.sfuiOldGodContainer.frame then
        containerPanel.sfuiOldGodContainer.frame:Hide()
    end
    if containerPanel.sfuiFallenSanctumContainer and containerPanel.sfuiFallenSanctumContainer.frame then
        containerPanel.sfuiFallenSanctumContainer.frame:Hide()
    end
    if containerPanel.sfuiNecrolordContainer and containerPanel.sfuiNecrolordContainer.frame then
        containerPanel.sfuiNecrolordContainer.frame:Hide()
    end

    if not containerPanel.sfuiMawContainer then
        local bFrame = CreateFrame("Frame", nil, containerPanel)
        bFrame:SetAllPoints(containerPanel)
        bFrame:SetFrameLevel(math.max(1, (containerPanel:GetFrameLevel() or 1)))

        local solid = containerPanel:CreateTexture(nil, "BACKGROUND", nil, -5)
        solid:SetAllPoints(containerPanel)
        solid:SetColorTexture(pal.containerColor[1], pal.containerColor[2], pal.containerColor[3], 0.88)

        local function makePiece(subLevel)
            return bFrame:CreateTexture(nil, "BORDER", nil, subLevel or 1)
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
        local texPath = GetMawTexture("stats_border.png")
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

        containerPanel.sfuiMawContainer = {
            frame = bFrame,
            solid = solid,
        }
    end

    local bFrame = containerPanel.sfuiMawContainer.frame
    bFrame:SetFrameLevel(math.max(1, (containerPanel:GetFrameLevel() or 1)))
    bFrame:Show()
    if containerPanel.SetBackdrop then
        containerPanel:SetBackdrop(nil)
    end
end

-- Custom ApplyHeader implementation with Maw stats header banner
function mawTheme.ApplyHeader(header, theme)
    if not header then return end
    local pal = sfui.theme.GetPalette()

    if not header.sfuiMawHeader then
        local bg = header:CreateTexture(nil, "BACKGROUND", nil, 1)
        bg:SetAllPoints(header)
        bg:SetTexture(GetMawTexture("stats_header.png"))
        header.sfuiMawHeader = bg
    end

    header.sfuiMawHeader:Show()
    if header.sfuiOldGodHeader then header.sfuiOldGodHeader:Hide() end
    if header.sfuiFallenSanctumHeader then header.sfuiFallenSanctumHeader:Hide() end
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

sfui.theme.RegisterTheme(mawTheme)

-- Register aliases for "the_maw" and "themaw"
local regThemes, _ = sfui.theme.GetRegisteredThemes()
if regThemes then
    regThemes["the_maw"] = mawTheme
    regThemes["themaw"] = mawTheme
    if sfui.theme.palettes then
        sfui.theme.palettes["the_maw"] = mawTheme.colors
        sfui.theme.palettes["themaw"] = mawTheme.colors
    end
end
