local addonName, addon = ...
sfui = sfui or {}
sfui.chat = sfui.chat or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/chat/chat_frame.lua
--  UIParent-parented chat panels wired to sfui.theme, reversible Blizzard
--  chrome stripping, slim 3px scrollbar, EventRegistry editbox styling,
--  corner copy/scroll buttons, opt-in idle fade, and built-in sfui.movers.
-- ══════════════════════════════════════════════════════════════════════════════

local chat = sfui.chat
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Timer = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown
local GetCursorPosition = _G.GetCursorPosition
local GetTime = _G.GetTime
local MouseIsOver = _G.MouseIsOver
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsMouseButtonDown = _G.IsMouseButtonDown
local hooksecurefunc = _G.hooksecurefunc
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local math_abs = math.abs
local pairs = _G.pairs
local ipairs = _G.ipairs
local type = _G.type
local tonumber = _G.tonumber

local issecretvalue = chat.issecretvalue
local CFD = chat.CFD
local PAD = chat.PAD
local POINT_FRAC = chat.POINT_FRAC
local rawClearAllPoints = chat.rawClearAllPoints
local rawSetPoint = chat.rawSetPoint

local EB_OWNER = "sfui_chat_eb"
local CHROME_UPDATE_KEY = "sfui_chat_chrome"
local TAB_FADE_DELAY = 1.5
local TAB_FADE_IN_SPEED = 6.0
local TAB_FADE_OUT_SPEED = 1.6

local EDITBOX_TEXTURE_SUFFIXES = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local mainPanel = nil
local copyBtn = nil
local scrollBtn = nil
local ebCallbacksRegistered = false
local ebHooksInstalled = false
local frameEnabled = false

local lastActivityTime = 0
local currentChromeAlpha = 1.0
local lastTabActivityTime = 0
local currentTabAlpha = 1.0
local isPanelHovered = false

-- ─────────────────────────────────────────────────────────────────────────────
--  Shared Backdrop & Theme Application Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function apply_flat(frame, bg, border)
    if not frame then return end
    if sfui.widgets and sfui.widgets.set_pixel_snapping then
        sfui.widgets.set_pixel_snapping(frame)
    end
    if sfui.widgets and sfui.widgets.apply_flat_backdrop then
        sfui.widgets.apply_flat_backdrop(frame, bg, border)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        if bg then frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1) end
        if border then frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1) end
    end
end

local function style_panel_bg(panel, d)
    if not panel then return end
    local bgA = chat.Get("bg_alpha", 0.0)
    local bdA = chat.Get("border_alpha", 0.0)
    local useTheme = chat.Get("use_theme", true) == true

    if sfui.theme and sfui.theme.ApplyChatPanelStyle then
        sfui.theme.ApplyChatPanelStyle(panel, bgA, bdA, useTheme)
    else
        local colors = chat.GetColors()
        apply_flat(panel, colors.bg, colors.border)
    end

    if d and d.scrollTrack then
        d.scrollTrack:SetFrameLevel(math_max(10, (panel:GetFrameLevel() or 5) + 4))
    end
    if panel == mainPanel then
        if copyBtn then copyBtn:SetFrameLevel(math_max(20, (panel:GetFrameLevel() or 5) + 10)) end
        if scrollBtn then scrollBtn:SetFrameLevel(math_max(20, (panel:GetFrameLevel() or 5) + 10)) end
    end
end

local function strip_texture_regions(container, savedStore)
    if not container or not container.GetRegions then return end
    local regions = { container:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.IsObjectType and r:IsObjectType("Texture") and not r._sfuiOwned then
            if savedStore and savedStore[r] == nil then
                local tex = r.GetTexture and r:GetTexture()
                local atlas = r.GetAtlas and r:GetAtlas()
                local alpha = r.GetAlpha and r:GetAlpha()
                savedStore[r] = {
                    tex = (not issecretvalue(tex)) and tex or nil,
                    atlas = (not issecretvalue(atlas)) and atlas or nil,
                    alpha = (not issecretvalue(alpha) and type(alpha) == "number") and alpha or 1,
                }
            end
            if r.SetTexture then r:SetTexture(nil) end
            if r.SetAtlas then r:SetAtlas("") end
            if r.SetAlpha then r:SetAlpha(0) end
        end
    end
end

local function restore_texture_regions(savedStore)
    if not savedStore then return end
    for r, info in pairs(savedStore) do
        if r then
            if info.atlas and info.atlas ~= "" and r.SetAtlas then
                r:SetAtlas(info.atlas)
            elseif info.tex and r.SetTexture then
                r:SetTexture(info.tex)
            end
            if r.SetAlpha and info.alpha ~= nil then
                r:SetAlpha(info.alpha)
            end
        end
    end
end

local function set_mouse_pair(f, enabled)
    if not f then return end
    if f.SetMouseClickEnabled then
        f:SetMouseClickEnabled(enabled)
    elseif f.EnableMouse then
        f:EnableMouse(enabled)
    end
    if f.SetMouseMotionEnabled then
        f:SetMouseMotionEnabled(enabled)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Panel Geometry, Strata & Visibility (All UIParent-parented)
-- ─────────────────────────────────────────────────────────────────────────────

local function sync_panel_strata_level(cf, bg)
    local cfStrata = (cf.GetFrameStrata and cf:GetFrameStrata()) or "LOW"
    local cfLevel = (cf.GetFrameLevel and cf:GetFrameLevel()) or 1
    if cfLevel > 1 then
        if bg:GetFrameStrata() ~= cfStrata then bg:SetFrameStrata(cfStrata) end
        if bg:GetFrameLevel() ~= cfLevel - 1 then bg:SetFrameLevel(cfLevel - 1) end
    else
        if bg:GetFrameStrata() ~= "BACKGROUND" then bg:SetFrameStrata("BACKGROUND") end
        if bg:GetFrameLevel() ~= 5 then bg:SetFrameLevel(5) end
    end
end

local function sync_panel_rect(cf)
    local d = CFD(cf)
    local bg = d and d.bg
    if not bg then return end
    local l, t, r, b = cf:GetLeft(), cf:GetTop(), cf:GetRight(), cf:GetBottom()
    if not (l and t and r and b) then return end
    if issecretvalue(l) or issecretvalue(t) or issecretvalue(r) or issecretvalue(b) then
        return
    end
    local cfScale = (cf.GetEffectiveScale and cf:GetEffectiveScale()) or 1
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if uiScale <= 0 then uiScale = 1 end
    local k = cfScale / uiScale

    local pl = l * k - PAD.l
    local pt = t * k + PAD.t
    local pr = r * k + PAD.r
    local pb = b * k - PAD.b

    if d._pl and math_abs(d._pl - pl) < 0.05 and math_abs(d._pt - pt) < 0.05
        and math_abs(d._pr - pr) < 0.05 and math_abs(d._pb - pb) < 0.05 then
        return
    end
    d._pl, d._pt, d._pr, d._pb = pl, pt, pr, pb

    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pl, pt)
    bg:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", pr, pb)
end

local function sync_panel_visibility(cf, d)
    if not (d and d.bg) then return end
    if not sfui.IsModuleEnabled("chat") then
        d.bg:Hide()
        return
    end
    if cf == _G.ChatFrame1 then
        local active = chat.GetActiveChatFrame()
        local show = (cf:IsShown() and true or false)
            or (active and active.isDocked and active:IsShown() and true or false)
        d.bg:SetShown(show)
    else
        d.bg:SetShown((not cf.isDocked and cf:IsShown()) and true or false)
    end
end

local function ensure_panel(cf, d)
    if d.bg then return d.bg end
    local panelName = (cf == _G.ChatFrame1) and "SfuiChatPanel" or nil
    local bg = CreateFrame("Frame", panelName, UIParent, "BackdropTemplate")
    bg:EnableMouse(false)
    sync_panel_strata_level(cf, bg)
    d.bg = bg
    if cf == _G.ChatFrame1 then
        mainPanel = bg
    end
    style_panel_bg(bg, d)
    return bg
end

function chat.GetMainPanel()
    return mainPanel
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Chrome Stripping & Native Scrollbar Suppression
-- ─────────────────────────────────────────────────────────────────────────────

local function apply_scrollbar_mode(cf)
    local bar = cf.ScrollBar
    if not bar then return end
    local hideStock = sfui.IsModuleEnabled("chat") and (chat.Get("custom_scrollbar", true) == true)
    if hideStock then
        if bar.Track then bar.Track:SetAlpha(0) end
        if bar.Back then bar.Back:SetAlpha(0); set_mouse_pair(bar.Back, false) end
        if bar.Forward then bar.Forward:SetAlpha(0); set_mouse_pair(bar.Forward, false) end
        set_mouse_pair(bar, false)
        set_mouse_pair(bar.Track, false)
        set_mouse_pair(bar.Track and bar.Track.Thumb, false)
    else
        if bar.Track then bar.Track:SetAlpha(1) end
        if bar.Back then bar.Back:SetAlpha(1); set_mouse_pair(bar.Back, true) end
        if bar.Forward then bar.Forward:SetAlpha(1); set_mouse_pair(bar.Forward, true) end
        set_mouse_pair(bar, true)
        set_mouse_pair(bar.Track, true)
        set_mouse_pair(bar.Track and bar.Track.Thumb, true)
    end
end

local function strip_chat_chrome(cf, d)
    if not d.strippedTex then d.strippedTex = {} end
    strip_texture_regions(cf, d.strippedTex)

    if cf.Background then
        cf.Background:SetAlpha(0)
        strip_texture_regions(cf.Background, d.strippedTex)
    end

    local name = cf.GetName and cf:GetName()
    local btnFrame = name and _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(0)
        if btnFrame.EnableMouse then btnFrame:EnableMouse(false) end
        strip_texture_regions(btnFrame, d.strippedTex)
    end

    if cf.ScrollToBottomButton then
        local sb = cf.ScrollToBottomButton
        sb:SetAlpha(0)
        if sb.EnableMouse then sb:EnableMouse(false) end
        sb:Hide()
        local sbd = CFD(sb)
        if not sbd.hideHooked and sb.HookScript then
            sbd.hideHooked = true
            sb:HookScript("OnShow", function(self)
                if sfui.IsModuleEnabled("chat") then
                    self:Hide()
                end
            end)
        end
    end

    if cf.SetClampedToScreen then cf:SetClampedToScreen(false) end
    if cf.SetClampRectInsets then cf:SetClampRectInsets(0, 0, 0, 0) end
    if cf.SetIndentedWordWrap then cf:SetIndentedWordWrap(true) end
    if cf.SetHyperlinksEnabled then cf:SetHyperlinksEnabled(true) end

    apply_scrollbar_mode(cf)
end

local function restore_chat_chrome(cf, d)
    if d.strippedTex then
        restore_texture_regions(d.strippedTex)
    end
    if cf.Background then
        cf.Background:SetAlpha(1)
    end
    local name = cf.GetName and cf:GetName()
    local btnFrame = name and _G[name .. "ButtonFrame"]
    if btnFrame then
        btnFrame:SetAlpha(1)
        if btnFrame.EnableMouse then btnFrame:EnableMouse(true) end
    end
    if cf.ScrollToBottomButton then
        cf.ScrollToBottomButton:SetAlpha(1)
        if cf.ScrollToBottomButton.EnableMouse then
            cf.ScrollToBottomButton:EnableMouse(true)
        end
    end
    apply_scrollbar_mode(cf)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Slim 3px Flat Scrollbar (Shown Only While Scrolled Up)
-- ─────────────────────────────────────────────────────────────────────────────

local function update_corner_buttons()
    if not (copyBtn or scrollBtn) then return end
    if not sfui.IsModuleEnabled("chat") then
        if copyBtn then copyBtn:Hide() end
        if scrollBtn then scrollBtn:Hide() end
        return
    end

    local mode = chat.Get("copy_button", "hover")
    if copyBtn then
        if mode == "hidden" then
            copyBtn:Hide()
        elseif mode == "always" then
            copyBtn:Show()
            local btnOver = MouseIsOver and MouseIsOver(copyBtn)
            copyBtn:SetAlpha((isPanelHovered or btnOver) and 1.0 or 0.55)
        else -- "hover"
            local btnOver = copyBtn:IsShown() and MouseIsOver and MouseIsOver(copyBtn)
            if isPanelHovered or btnOver then
                copyBtn:Show()
                copyBtn:SetAlpha(btnOver and 1.0 or 0.85)
            else
                copyBtn:Hide()
            end
        end
    end

    if scrollBtn then
        local activeCF = chat.GetActiveChatFrame()
        local scrolled = false
        if activeCF and activeCF.GetScrollOffset then
            local off = activeCF:GetScrollOffset()
            if not issecretvalue(off) and type(off) == "number" and off > 0 then
                scrolled = true
            end
        end
        scrollBtn:SetShown(scrolled)
    end
end

local function sync_scrollbar_host(cf, d, track)
    local host = (cf and cf.isDocked and mainPanel) or (d and d.bg)
    if not (host and track) then return nil end
    if track:GetParent() ~= host then
        track:SetParent(host)
        track:ClearAllPoints()
        track:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2, -4)
        track:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 4)
        track:SetFrameLevel(math_max(10, (host:GetFrameLevel() or 5) + 4))
    end
    return host
end

local function update_scrollbar(cf)
    local d = CFD(cf)
    local track, thumb = d and d.scrollTrack, d and d.scrollThumb
    if not (track and thumb) then return end
    local host = sync_scrollbar_host(cf, d, track)
    if not host or not sfui.IsModuleEnabled("chat") or not chat.Get("custom_scrollbar", true) then
        track:Hide()
        return
    end
    if cf.isDocked and cf ~= chat.GetActiveChatFrame() then
        track:Hide()
        return
    end
    if not (cf.GetMaxScrollRange and cf.GetScrollOffset) then
        track:Hide()
        return
    end

    local range = cf:GetMaxScrollRange()
    local offset = cf:GetScrollOffset()
    if issecretvalue(range) or issecretvalue(offset) or type(range) ~= "number" or type(offset) ~= "number" then
        track:Hide()
        return
    end

    local show = (range > 0) and (offset > 0 or d.sbDragging)
    if not show then
        track:Hide()
        return
    end

    track:Show()
    local trackH = track:GetHeight()
    if not trackH or trackH <= 0 then return end
    local vis = (cf.GetNumVisibleLines and cf:GetNumVisibleLines()) or 12
    local total = math_max(1, range + vis)
    local thumbH = math_max(18, math_min(trackH, trackH * (vis / total)))
    thumb:SetHeight(thumbH)

    local pct = offset / math_max(1, range)
    thumb:ClearAllPoints()
    thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, pct * (trackH - thumbH))
end

local function scroll_cf_from_cursor(cf, d)
    local track, thumb = d.scrollTrack, d.scrollThumb
    if not (track and thumb and cf.GetMaxScrollRange and cf.SetScrollOffset) then return end
    local trackH = track:GetHeight() or 0
    local thumbH = thumb:GetHeight() or 18
    local travel = trackH - thumbH
    if travel <= 0 then return end
    local bottom = track:GetBottom()
    if not bottom or issecretvalue(bottom) then return end
    local scale = track:GetEffectiveScale() or 1
    local _, cy = GetCursorPosition()
    if not cy or issecretvalue(cy) then return end
    local localY = (cy / scale) - bottom - (d.sbDragOffset or (thumbH * 0.5))
    local pct = math_max(0, math_min(1, localY / travel))
    local range = cf:GetMaxScrollRange()
    if issecretvalue(range) or type(range) ~= "number" then return end
    cf:SetScrollOffset(math_floor(pct * range + 0.5))
    update_scrollbar(cf)
    update_corner_buttons()
end

local function ensure_scrollbar(cf, d)
    if d.scrollTrack then return end
    local host = (cf and cf.isDocked and mainPanel) or d.bg
    if not host then return end
    local track = CreateFrame("Button", nil, host)
    track:SetWidth(8)
    track:SetPoint("TOPRIGHT", host, "TOPRIGHT", -2, -4)
    track:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 4)
    track:SetFrameLevel(math_max(10, (host:GetFrameLevel() or 5) + 4))
    track:Hide()

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb._sfuiOwned = true
    thumb:SetWidth(3)
    thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, 0)
    local colors = chat.GetColors()
    thumb:SetColorTexture(colors.scrollThumb[1], colors.scrollThumb[2], colors.scrollThumb[3], colors.scrollThumb[4])

    d.scrollTrack = track
    d.scrollThumb = thumb

    local function drag_tick(self)
        if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") then
            d.sbDragging = nil
            self:SetScript("OnUpdate", nil)
            update_scrollbar(cf)
            return
        end
        scroll_cf_from_cursor(cf, d)
    end

    track:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local tTop, tBot = thumb:GetTop(), thumb:GetBottom()
        local scale = self:GetEffectiveScale() or 1
        local _, cy = GetCursorPosition()
        if cy and not issecretvalue(cy) and tTop and tBot and not issecretvalue(tTop) and not issecretvalue(tBot) then
            cy = cy / scale
            if cy <= tTop and cy >= tBot then
                d.sbDragOffset = cy - tBot
            else
                d.sbDragOffset = (thumb:GetHeight() or 18) * 0.5
            end
        else
            d.sbDragOffset = (thumb:GetHeight() or 18) * 0.5
        end
        d.sbDragging = true
        scroll_cf_from_cursor(cf, d)
        self:SetScript("OnUpdate", drag_tick)
    end)

    track:SetScript("OnMouseUp", function(self)
        d.sbDragging = nil
        self:SetScript("OnUpdate", nil)
        update_scrollbar(cf)
    end)

    if not d.scrollHooked then
        d.scrollHooked = true
        if cf.AddOnDisplayRefreshedCallback then
            cf:AddOnDisplayRefreshedCallback(function(frame)
                if not sfui.IsModuleEnabled("chat") then return end
                update_scrollbar(frame)
                update_corner_buttons()
                if chat.WakeIdleFade then chat.WakeIdleFade() end
            end)
        elseif hooksecurefunc and cf.SetScrollOffset then
            hooksecurefunc(cf, "SetScrollOffset", function(frame)
                if not sfui.IsModuleEnabled("chat") then return end
                update_scrollbar(frame)
                update_corner_buttons()
            end)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Mousewheel Boost & Subtle Corner Micro-Buttons (Themed / Flat)
-- ─────────────────────────────────────────────────────────────────────────────

local function ensure_wheel_boost(cf, d)
    if d.wheelHooked or not cf.HookScript then return end
    if cf.isTemporary then return end
    d.wheelHooked = true
    cf:HookScript("OnMouseWheel", function(self, delta)
        if not sfui.IsModuleEnabled("chat") then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if delta > 0 and self.ScrollToTop then
                self:ScrollToTop()
            elseif delta <= 0 and self.ScrollToBottom then
                self:ScrollToBottom()
            end
        elseif IsControlKeyDown and IsControlKeyDown() then
            for _ = 1, 4 do
                if delta > 0 and self.ScrollUp then self:ScrollUp() elseif self.ScrollDown then self:ScrollDown() end
            end
        else
            for _ = 1, 2 do
                if delta > 0 and self.ScrollUp then self:ScrollUp() elseif self.ScrollDown then self:ScrollDown() end
            end
        end
        update_scrollbar(self)
        update_corner_buttons()
        if chat.WakeIdleFade then chat.WakeIdleFade() end
    end)
end

local function style_corner_buttons()
    local colors = chat.GetColors()
    local useTheme = chat.Get("use_theme", true) == true
    local hasButtonTheme = useTheme and sfui.theme and sfui.theme.ApplyButtonStyle

    if copyBtn then
        if hasButtonTheme then
            sfui.theme.ApplyButtonStyle(copyBtn, false)
        else
            if sfui.theme and sfui.theme.ClearFrameThemeLayers then
                sfui.theme.ClearFrameThemeLayers(copyBtn)
            end
            apply_flat(copyBtn, colors.tabBg, { 0, 0, 0, 0.85 })
            if copyBtn.fs then
                copyBtn.fs:SetTextColor(colors.tabText[1], colors.tabText[2], colors.tabText[3], 1)
            end
        end
    end

    if scrollBtn then
        if hasButtonTheme then
            sfui.theme.ApplyButtonStyle(scrollBtn, false)
        else
            if sfui.theme and sfui.theme.ClearFrameThemeLayers then
                sfui.theme.ClearFrameThemeLayers(scrollBtn)
            end
            apply_flat(scrollBtn, colors.tabActiveBg, { 0, 0, 0, 0.85 })
        end
        if scrollBtn.arrow then
            scrollBtn.arrow:SetVertexColor(colors.accent[1], colors.accent[2], colors.accent[3], 1)
        elseif scrollBtn.label then
            scrollBtn.label:SetTextColor(colors.accent[1], colors.accent[2], colors.accent[3], 1)
        end
    end

    update_corner_buttons()
end

local function ensure_corner_buttons(panel1)
    if not panel1 or copyBtn then return end
    local colors = chat.GetColors()
    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file()) or "Fonts\\FRIZQT__.TTF"

    copyBtn = CreateFrame("Button", "SfuiChatCopyButton", panel1, "BackdropTemplate")
    copyBtn:SetSize(38, 18)
    copyBtn:SetPoint("TOPRIGHT", panel1, "TOPRIGHT", -5, -5)
    copyBtn:SetFrameStrata("MEDIUM")
    copyBtn:SetFrameLevel(math_max(20, (panel1:GetFrameLevel() or 5) + 10))

    local cfs = copyBtn:CreateFontString(nil, "OVERLAY")
    cfs:SetFont(fontFile, 10, "")
    cfs:SetPoint("CENTER", 0, 0)
    cfs:SetTextColor(colors.tabText[1], colors.tabText[2], colors.tabText[3], 1)
    cfs:SetText("copy")
    copyBtn.fs = cfs
    copyBtn.label = cfs

    copyBtn:SetScript("OnClick", function()
        if chat.OpenCopyWindow then
            chat.OpenCopyWindow()
        end
    end)
    copyBtn:HookScript("OnEnter", function(self)
        self:SetAlpha(1.0)
        if not (chat.Get("use_theme", true) and sfui.theme and sfui.theme.ApplyButtonStyle) then
            local c = chat.GetColors()
            self:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], 1)
            if self.fs then
                self.fs:SetTextColor(c.accent[1], c.accent[2], c.accent[3], 1)
            end
        end
    end)
    copyBtn:HookScript("OnLeave", function(self)
        if not (chat.Get("use_theme", true) and sfui.theme and sfui.theme.ApplyButtonStyle) then
            local c = chat.GetColors()
            self:SetBackdropBorderColor(0, 0, 0, 0.85)
            if self.fs then
                self.fs:SetTextColor(c.tabText[1], c.tabText[2], c.tabText[3], 1)
            end
        end
        update_corner_buttons()
    end)

    if sfui.widgets and sfui.widgets.attach_tooltip then
        sfui.widgets.attach_tooltip(copyBtn, "copy chat", { "click to copy active chat tab", "slash command: /copy" }, "ANCHOR_TOP")
    end

    scrollBtn = CreateFrame("Button", "SfuiChatScrollBottomButton", panel1, "BackdropTemplate")
    scrollBtn:SetSize(18, 18)
    scrollBtn:SetPoint("BOTTOMRIGHT", panel1, "BOTTOMRIGHT", -10, 5)
    scrollBtn:SetFrameStrata("MEDIUM")
    scrollBtn:SetFrameLevel(math_max(20, (panel1:GetFrameLevel() or 5) + 10))
    scrollBtn.customOnLeave = true

    if sfui.theme and sfui.theme.HasAtlas and sfui.theme.HasAtlas("minimal-scrollbar-arrow-returntobottom") then
        local arrow = scrollBtn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(11, 11)
        arrow:SetPoint("CENTER", 0, 0)
        arrow:SetAtlas("minimal-scrollbar-arrow-returntobottom")
        scrollBtn.arrow = arrow
    else
        local sfs = scrollBtn:CreateFontString(nil, "OVERLAY")
        sfs:SetFont(fontFile, 11, "")
        sfs:SetPoint("CENTER", 0, 0)
        sfs:SetText("v")
        scrollBtn.label = sfs
    end

    scrollBtn:SetScript("OnClick", function()
        local acf = chat.GetActiveChatFrame()
        if acf and acf.ScrollToBottom then
            acf:ScrollToBottom()
            update_scrollbar(acf)
            update_corner_buttons()
        end
    end)
    scrollBtn:HookScript("OnEnter", function(self)
        if not (chat.Get("use_theme", true) and sfui.theme and sfui.theme.ApplyButtonStyle) then
            local c = chat.GetColors()
            self:SetBackdropBorderColor(c.accent[1], c.accent[2], c.accent[3], 1)
        end
    end)
    scrollBtn:HookScript("OnLeave", function(self)
        if not (chat.Get("use_theme", true) and sfui.theme and sfui.theme.ApplyButtonStyle) then
            self:SetBackdropBorderColor(0, 0, 0, 0.85)
        end
    end)

    if sfui.widgets and sfui.widgets.attach_tooltip then
        sfui.widgets.attach_tooltip(scrollBtn, "scroll to bottom", "jump to latest messages", "ANCHOR_LEFT")
    end

    scrollBtn:Hide()
    style_corner_buttons()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Clean Flat EditBox (EventRegistry Only on Retail/Forever; Zero HookScript)
-- ─────────────────────────────────────────────────────────────────────────────

local function get_editbox(cf)
    if cf and cf.editBox then return cf.editBox end
    local name = cf and cf.GetName and cf:GetName()
    return name and _G[name .. "EditBox"] or nil
end

local function apply_editbox_position(cf)
    local eb = get_editbox(cf)
    if not eb then return end
    if InCombatLockdown and InCombatLockdown() and cf and cf.isTemporary then return end
    local anchorCF = ((cf == _G.ChatFrame1) or (cf and cf.isDocked)) and _G.ChatFrame1 or cf
    if not anchorCF then return end

    -- Anchor Blizzard EditBox solely to Blizzard ChatFrame (never to our addon panel).
    local pos = chat.Get("editbox_pos", "bottom")
    eb:ClearAllPoints()
    eb:SetHeight(24)
    if pos == "top" then
        local topY = (chat.Get("ghost_tabs", true) and 25) or 23
        eb:SetPoint("BOTTOMLEFT", anchorCF, "TOPLEFT", -PAD.l, PAD.t + topY)
        eb:SetPoint("BOTTOMRIGHT", anchorCF, "TOPRIGHT", PAD.r, PAD.t + topY)
    else
        eb:SetPoint("TOPLEFT", anchorCF, "BOTTOMLEFT", -PAD.l, -(PAD.b + 2))
        eb:SetPoint("TOPRIGHT", anchorCF, "BOTTOMRIGHT", PAD.r, -(PAD.b + 2))
    end
end

local function update_editbox_visuals(eb, focused)
    if not eb then return end
    local cf = (eb.chatFrame) or (eb.GetParent and eb:GetParent())
    local d = CFD(cf)
    if not (d and d.ebBg) then return end

    local colors = chat.GetColors()
    local useTheme = chat.Get("use_theme", true) == true
    local r, g, b, a = 0.14, 0.14, 0.16, 0.90

    if useTheme and sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(d.ebBg)
        local pal = sfui.theme.GetPalette and sfui.theme.GetPalette()
        local pbc = pal and pal.borderColor
        if pbc and (pbc[4] or 0) > 0.01 then
            r, g, b, a = pbc[1], pbc[2], pbc[3], 0.90
        else
            r, g, b, a = colors.innerBorder[1], colors.innerBorder[2], colors.innerBorder[3], 0.55
        end
    else
        if sfui.theme and sfui.theme.ClearFrameThemeLayers then
            sfui.theme.ClearFrameThemeLayers(d.ebBg)
        end
        apply_flat(d.ebBg, colors.ebBg, { r, g, b, a })
    end

    if focused and eb.GetAttribute then
        local ct = eb:GetAttribute("chatType")
        if ct and not issecretvalue(ct) and type(ct) == "string" and _G.ChatTypeInfo then
            local key = ct
            if ct == "CHANNEL" then
                local ch = eb:GetAttribute("channelTarget")
                if ch and not issecretvalue(ch) and type(ch) == "number" then
                    key = "CHANNEL" .. ch
                end
            end
            local info = _G.ChatTypeInfo[key] or _G.ChatTypeInfo[ct]
            if info and info.r and info.g and info.b then
                r, g, b, a = info.r, info.g, info.b, 0.90
            else
                r, g, b, a = colors.accent[1], colors.accent[2], colors.accent[3], 0.90
            end
        else
            r, g, b, a = colors.accent[1], colors.accent[2], colors.accent[3], 0.90
        end
    end

    if d.ebBg.SetBackdropBorderColor then
        d.ebBg:SetBackdropBorderColor(r, g, b, a)
    end
end

local function is_editbox_focused(eb)
    return (eb and eb.HasFocus and eb:HasFocus()) and true or false
end

local function has_unsent_text(eb)
    if not (eb and eb.GetText) then return false end
    local txt = eb:GetText()
    return type(txt) == "string" and not issecretvalue(txt) and txt ~= ""
end

local function show_active_editbox(eb)
    if not (eb and sfui.IsModuleEnabled("chat")) then return end
    local cf = eb.chatFrame or (eb.GetParent and eb:GetParent())
    local d = CFD(cf)
    if cf then
        apply_editbox_position(cf)
    end
    if eb.SetAlpha then eb:SetAlpha(1) end
    if d and d.ebBg then
        d.ebBg:SetFrameStrata("DIALOG")
        d.ebBg:SetFrameLevel(math_max(1, ((eb.GetFrameLevel and eb:GetFrameLevel()) or 5) - 1))
        d.ebBg:Show()
        update_editbox_visuals(eb, true)
    end
    if chat.WakeIdleFade then chat.WakeIdleFade() end
    if chat.WakeTabFade then chat.WakeTabFade() end
end

local function hide_inactive_editbox(eb, forceHide)
    if not (eb and sfui.IsModuleEnabled("chat")) then return end
    if not forceHide and is_editbox_focused(eb) then return end
    local cf = eb.chatFrame or (eb.GetParent and eb:GetParent())
    local d = CFD(cf)
    if d and d.hidingEb then return end
    if not forceHide and eb.IsShown and eb:IsShown() and has_unsent_text(eb) then
        if d and d.ebBg then
            d.ebBg:SetFrameStrata("DIALOG")
            d.ebBg:SetFrameLevel(math_max(1, ((eb.GetFrameLevel and eb:GetFrameLevel()) or 5) - 1))
            d.ebBg:Show()
            update_editbox_visuals(eb, false)
        end
        return
    end
    if d then d.hidingEb = true end
    if d and d.ebBg then d.ebBg:Hide() end
    if eb.SetAlpha then eb:SetAlpha(0) end
    if eb.IsShown and eb:IsShown() and eb.Hide then
        eb:Hide()
    end
    if d then d.hidingEb = nil end
end

local function on_eb_show(_, eb)
    if not sfui.IsModuleEnabled("chat") then return end
    if is_editbox_focused(eb) or (eb and eb == _G.ACTIVE_CHAT_EDIT_BOX) then
        show_active_editbox(eb)
        return
    end
    local cf = eb and (eb.chatFrame or (eb.GetParent and eb:GetParent()))
    local d = CFD(cf)
    if d and d.ebBg and not has_unsent_text(eb) then
        d.ebBg:Hide()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if eb and sfui.IsModuleEnabled("chat") and not is_editbox_focused(eb) and eb ~= _G.ACTIVE_CHAT_EDIT_BOX then
                hide_inactive_editbox(eb, false)
            end
        end)
    end
end

local function on_eb_hide(_, eb)
    local cf = (eb and eb.chatFrame) or (eb and eb.GetParent and eb:GetParent())
    local d = CFD(cf)
    if d and d.ebBg then
        d.ebBg:Hide()
    end
end

local function on_eb_focus_gained(_, eb)
    if not sfui.IsModuleEnabled("chat") then return end
    show_active_editbox(eb)
end

local function on_eb_focus_lost(_, eb)
    if not sfui.IsModuleEnabled("chat") then return end
    hide_inactive_editbox(eb, false)
end

local function install_editbox_hooks()
    if ebHooksInstalled or not hooksecurefunc then return end
    ebHooksInstalled = true

    local util = _G.ChatFrameUtil
    local function hook_api(utilKey, globalName, fn)
        if util and util[utilKey] then
            hooksecurefunc(util, utilKey, fn)
        elseif _G[globalName] then
            hooksecurefunc(globalName, fn)
        end
    end

    hook_api("ActivateChat", "ChatEdit_ActivateChat", function(eb)
        if sfui.IsModuleEnabled("chat") and eb then
            show_active_editbox(eb)
        end
    end)
    hook_api("DeactivateChat", "ChatEdit_DeactivateChat", function(eb)
        if sfui.IsModuleEnabled("chat") and eb then
            hide_inactive_editbox(eb, true)
        end
    end)
    hook_api("SetLastActiveWindow", "ChatEdit_SetLastActiveWindow", function(eb)
        if sfui.IsModuleEnabled("chat") and eb and eb ~= _G.ACTIVE_CHAT_EDIT_BOX then
            hide_inactive_editbox(eb, false)
        end
    end)
end

local function register_editbox_callbacks()
    install_editbox_hooks()
    if ebCallbacksRegistered then return end
    local ER = _G.EventRegistry
    if ER and ER.RegisterCallback and not sfui.isEra then
        ebCallbacksRegistered = true
        ER:RegisterCallback("ChatFrame.OnEditBoxShow", on_eb_show, EB_OWNER)
        ER:RegisterCallback("ChatFrame.OnEditBoxHide", on_eb_hide, EB_OWNER)
        ER:RegisterCallback("ChatFrame.OnEditBoxFocusGained", on_eb_focus_gained, EB_OWNER)
        ER:RegisterCallback("ChatFrame.OnEditBoxFocusLost", on_eb_focus_lost, EB_OWNER)
    end
end

local function unregister_editbox_callbacks()
    if not ebCallbacksRegistered then return end
    ebCallbacksRegistered = false
    local ER = _G.EventRegistry
    if ER and ER.UnregisterCallback then
        ER:UnregisterCallback("ChatFrame.OnEditBoxShow", EB_OWNER)
        ER:UnregisterCallback("ChatFrame.OnEditBoxHide", EB_OWNER)
        ER:UnregisterCallback("ChatFrame.OnEditBoxFocusGained", EB_OWNER)
        ER:UnregisterCallback("ChatFrame.OnEditBoxFocusLost", EB_OWNER)
    end
end

local function skin_editbox(cf, d)
    local eb = get_editbox(cf)
    if not eb then return end
    local name = cf.GetName and cf:GetName()
    if not d.ebStripped then d.ebStripped = {} end
    if name then
        for i = 1, #EDITBOX_TEXTURE_SUFFIXES do
            local tex = _G[name .. "EditBox" .. EDITBOX_TEXTURE_SUFFIXES[i]]
            if tex then
                if d.ebStripped[tex] == nil then
                    local path = tex.GetTexture and tex:GetTexture()
                    local alpha = tex.GetAlpha and tex:GetAlpha()
                    d.ebStripped[tex] = {
                        tex = (not issecretvalue(path)) and path or nil,
                        alpha = (not issecretvalue(alpha) and type(alpha) == "number") and alpha or 1,
                    }
                end
                if tex.SetTexture then tex:SetTexture(nil) end
                if tex.SetAlpha then tex:SetAlpha(0) end
            end
        end
    end

    if not cf.isTemporary then
        if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
        if eb.SetClampedToScreen then eb:SetClampedToScreen(true) end
    end

    if not d.ebBg then
        local ebBg = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ebBg:EnableMouse(false)
        ebBg:SetFrameStrata("DIALOG")
        ebBg:SetFrameLevel(math_max(1, ((eb.GetFrameLevel and eb:GetFrameLevel()) or 5) - 1))
        ebBg:SetAllPoints(eb)
        ebBg:Hide()
        d.ebBg = ebBg
        update_editbox_visuals(eb, is_editbox_focused(eb))
    end

    if sfui.isEra and not d.eraEbHooked and not cf.isTemporary and eb.HookScript then
        d.eraEbHooked = true
        eb:HookScript("OnShow", function(self) on_eb_show(nil, self) end)
        eb:HookScript("OnHide", function(self) on_eb_hide(nil, self) end)
        eb:HookScript("OnEditFocusGained", function(self) on_eb_focus_gained(nil, self) end)
        eb:HookScript("OnEditFocusLost", function(self) on_eb_focus_lost(nil, self) end)
    end

    if is_editbox_focused(eb) then
        show_active_editbox(eb)
    else
        apply_editbox_position(cf)
        hide_inactive_editbox(eb, false)
    end
end

local function restore_editbox(cf, d)
    if d.ebBg then d.ebBg:Hide() end
    if d.ebStripped then
        restore_texture_regions(d.ebStripped)
    end
    local eb = get_editbox(cf)
    if eb then
        if eb.SetAlpha then eb:SetAlpha(1) end
        if _G.GetCVar and _G.GetCVar("chatStyle") == "im" and eb == _G.LAST_ACTIVE_CHAT_EDIT_BOX then
            if eb.Show then eb:Show() end
            if eb.SetAlpha then eb:SetAlpha(0.35) end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Non-Intrusive Font Handling (Native Fallback + Combat Log 14 Default)
-- ─────────────────────────────────────────────────────────────────────────────

local function is_combat_log(cf)
    if _G.IsCombatLog and _G.IsCombatLog(cf) then
        return true
    end
    return cf == _G.ChatFrame2 or cf == _G.COMBATLOG
end

local function apply_font_to_frame(cf, d)
    if not (cf and cf.SetFont and cf.GetFont) then return end
    if not d.origFontSaved then
        local f, s, fl = cf:GetFont()
        if not (issecretvalue(f) or issecretvalue(s) or issecretvalue(fl)) and f then
            d.origFontSaved = true
            d.origFont = { f, s or 14, fl or "" }
        end
    end

    local enabled = sfui.IsModuleEnabled("chat")
    local isCL = is_combat_log(cf)
    local override = chat.Get("font_override", false) == true

    if enabled and override then
        local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
        local rawSize = isCL and chat.Get("combatlog_font_size", 14) or chat.Get("font_size", 13)
        local size = math_max(8, math_min(28, rawSize))
        local outline = chat.Get("font_outline", "OUTLINE") or ""
        cf:SetFont(fontFile, size, outline)
        if cf.SetShadowOffset then cf:SetShadowOffset(1, -1) end
        if cf.SetShadowColor then cf:SetShadowColor(0, 0, 0, 0.85) end
    elseif enabled and isCL then
        local fontFile = (d.origFont and d.origFont[1]) or "Fonts\\FRIZQT__.TTF"
        local flags = (d.origFont and d.origFont[3]) or ""
        local size = math_max(8, math_min(28, chat.Get("combatlog_font_size", 14)))
        cf:SetFont(fontFile, size, flags)
    elseif d.origFont then
        cf:SetFont(d.origFont[1], d.origFont[2], d.origFont[3])
    end
end

function chat.ApplyFonts()
    chat.ForEachChatFrame(function(cf)
        local d = CFD(cf)
        if d then apply_font_to_frame(cf, d) end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Auto-Fading Tabs & Opt-In Idle Chrome Fade (Zero-Click-Interference)
-- ─────────────────────────────────────────────────────────────────────────────

local function sync_tab_alpha()
    if not chat.SetTabStripAlpha then return end
    local tabA = (chat.Get("tab_autofade", true) == true)
        and math_min(currentTabAlpha, currentChromeAlpha)
        or currentChromeAlpha
    chat.SetTabStripAlpha(tabA)
end

local function apply_panel_alpha(alpha)
    currentChromeAlpha = alpha
    if mainPanel then
        mainPanel:SetAlpha(alpha)
    end
    sync_tab_alpha()
end

local function apply_tab_alpha(alpha)
    currentTabAlpha = alpha
    sync_tab_alpha()
end

function chat.WakeIdleFade()
    lastActivityTime = GetTime and GetTime() or 0
    if currentChromeAlpha ~= 1.0 then
        apply_panel_alpha(1.0)
    end
end

function chat.WakeTabFade()
    lastTabActivityTime = GetTime and GetTime() or 0
    if currentTabAlpha ~= 1.0 then
        apply_tab_alpha(1.0)
    end
end

local function is_any_editbox_shown()
    local maxStatic = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, maxStatic do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb and eb:IsShown() and is_editbox_focused(eb) then return true end
    end
    return false
end

local function is_mouse_over_safe(f)
    if not (f and f.IsShown and f:IsShown() and MouseIsOver) then return false end
    local over = MouseIsOver(f)
    if issecretvalue(over) then return false end
    return over and true or false
end

local function on_chrome_tick(elapsed)
    if not sfui.IsModuleEnabled("chat") then return end
    local strip = chat.GetTabStrip and chat.GetTabStrip()
    local overPanel = is_mouse_over_safe(mainPanel)
    local overStrip = is_mouse_over_safe(strip)
    local overCopy = is_mouse_over_safe(copyBtn)
    local overScroll = is_mouse_over_safe(scrollBtn)
    local overQuickBar = is_mouse_over_safe(_G.CombatLogQuickButtonFrame_Custom)
    local overFloat = chat.IsFloatingHovered and chat.IsFloatingHovered()
    local hoverNow = (overPanel or overStrip or overCopy or overScroll or overQuickBar or overFloat) and true or false

    if hoverNow ~= isPanelHovered then
        isPanelHovered = hoverNow
        update_corner_buttons()
    elseif copyBtn and chat.Get("copy_button", "hover") == "hover" then
        update_corner_buttons()
    end

    local now = GetTime and GetTime() or 0
    local dt = elapsed or 0.1
    local editFocused = is_any_editbox_shown()
    local moversUnlocked = (sfui.movers and sfui.movers.isUnlocked) and true or false
    local dock = _G.GENERAL_CHAT_DOCK
    local overflowList = dock and dock.overflowButton and dock.overflowButton.list
    local overflowShown = (overflowList and overflowList.IsShown and overflowList:IsShown()) and true or false
    local editModeShown = (_G.EditModeManagerFrame and _G.EditModeManagerFrame.IsShown and _G.EditModeManagerFrame:IsShown()) and true or false
    local alertingTab = (chat.HasAlertingTab and chat.HasAlertingTab()) and true or false

    if chat.Get("idle_fade", false) then
        local active = hoverNow or editFocused or moversUnlocked
        if active then
            chat.WakeIdleFade()
        else
            local delay = math_max(2, chat.Get("idle_fade_delay", 15))
            local target = math_max(0, math_min(0.5, chat.Get("idle_fade_alpha", 0.0)))
            if (now - lastActivityTime) >= delay then
                if currentChromeAlpha > target then
                    apply_panel_alpha(math_max(target, currentChromeAlpha - dt * 2.5))
                end
            elseif currentChromeAlpha < 1.0 then
                apply_panel_alpha(math_min(1.0, currentChromeAlpha + dt * 5.0))
            end
        end
    elseif currentChromeAlpha ~= 1.0 then
        apply_panel_alpha(1.0)
    end

    if chat.Get("tab_autofade", true) == true then
        local tabActive = hoverNow or editFocused or moversUnlocked or editModeShown or overflowShown or alertingTab
        if tabActive then
            lastTabActivityTime = now
            if currentTabAlpha < 1.0 then
                apply_tab_alpha(math_min(1.0, currentTabAlpha + dt * TAB_FADE_IN_SPEED))
            end
        elseif (now - lastTabActivityTime) >= TAB_FADE_DELAY then
            if currentTabAlpha > 0.0 then
                apply_tab_alpha(math_max(0.0, currentTabAlpha - dt * TAB_FADE_OUT_SPEED))
            end
        end
    elseif currentTabAlpha ~= 1.0 then
        apply_tab_alpha(1.0)
    end
end

local function sync_chrome_tick_registration()
    if not (sfui.events and sfui.events.RegisterUpdate and sfui.events.UnregisterUpdate) then return end
    local needTick = sfui.IsModuleEnabled("chat") and (
        chat.Get("copy_button", "hover") == "hover"
        or chat.Get("idle_fade", false) == true
        or chat.Get("tab_autofade", true) == true
    )
    if needTick then
        sfui.events.RegisterUpdate(CHROME_UPDATE_KEY, 0.10, on_chrome_tick)
    else
        sfui.events.UnregisterUpdate(CHROME_UPDATE_KEY)
        isPanelHovered = false
        if currentChromeAlpha ~= 1.0 then
            apply_panel_alpha(1.0)
        end
        if currentTabAlpha ~= 1.0 then
            apply_tab_alpha(1.0)
        end
    end
end

function chat.RefreshIdleFade()
    chat.WakeIdleFade()
    if chat.Get("tab_autofade", true) == true then
        chat.WakeTabFade()
    elseif currentTabAlpha ~= 1.0 then
        apply_tab_alpha(1.0)
    end
    sync_chrome_tick_registration()
end

function chat.RefreshCornerControls()
    update_corner_buttons()
    sync_chrome_tick_registration()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Position, Size & Built-In sfui.movers Integration
-- ─────────────────────────────────────────────────────────────────────────────

local function apply_cf1_anchors(cf1, pos, customW, customH)
    local cfScale = (cf1.GetEffectiveScale and cf1:GetEffectiveScale()) or 1
    local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local invK = (cfScale > 0) and (uiScale / cfScale) or 1
    local scaleK = (uiScale > 0) and (cfScale / uiScale) or 1

    if customW > 0 or customH > 0 then
        local uiW = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
        local uiH = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 1080
        local curW = cf1.GetWidth and cf1:GetWidth()
        local curH = cf1.GetHeight and cf1:GetHeight()
        if not curW or issecretvalue(curW) then curW = 414 else curW = curW * scaleK end
        if not curH or issecretvalue(curH) then curH = 194 else curH = curH * scaleK end

        local panelW = math_max(200, (customW > 0) and customW or (curW + PAD.l + PAD.r))
        local panelH = math_max(80, (customH > 0) and customH or (curH + PAD.t + PAD.b))

        local panelLeft, panelBottom
        if pos and pos.point then
            local pt = pos.point
            local rpt = pos.relPoint or pt
            local f = POINT_FRAC[pt] or POINT_FRAC.BOTTOMLEFT
            local rf = POINT_FRAC[rpt] or POINT_FRAC.BOTTOMLEFT
            local px = pos.x or 0
            local py = pos.y or 0
            panelLeft = uiW * rf[1] + px - f[1] * panelW
            panelBottom = uiH * rf[2] + py - f[2] * panelH
        else
            local l = cf1.GetLeft and cf1:GetLeft()
            local b = cf1.GetBottom and cf1:GetBottom()
            if not (l and b) or issecretvalue(l) or issecretvalue(b) then return end
            panelLeft = l * scaleK - PAD.l
            panelBottom = b * scaleK - PAD.b
        end

        local cfL = panelLeft + PAD.l
        local cfB = panelBottom + PAD.b
        local cfR = cfL + (panelW - PAD.l - PAD.r)
        local cfT = cfB + (panelH - PAD.t - PAD.b)

        rawClearAllPoints(cf1)
        rawSetPoint(cf1, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", cfL * invK, cfB * invK)
        rawSetPoint(cf1, "TOPRIGHT", UIParent, "BOTTOMLEFT", cfR * invK, cfT * invK)
    elseif pos and pos.point then
        local pt = pos.point
        local rpt = pos.relPoint or pt
        local f = POINT_FRAC[pt] or POINT_FRAC.BOTTOMLEFT
        local px = pos.x or 0
        local py = pos.y or 0
        local cfX = px - (f[1] * (PAD.l + PAD.r) - PAD.l)
        local cfY = py - (f[2] * (PAD.t + PAD.b) - PAD.b)
        rawClearAllPoints(cf1)
        rawSetPoint(cf1, pt, UIParent, rpt, cfX * invK, cfY * invK)
    end
end

function chat.ApplyChatPosition()
    if not sfui.IsModuleEnabled("chat") then return end
    if _G.EditModeManagerFrame and _G.EditModeManagerFrame.IsShown and _G.EditModeManagerFrame:IsShown() then
        return
    end
    local cf1 = _G.ChatFrame1
    if not cf1 then return end

    local pos = chat.Get("position", nil)
    local customW = chat.Get("width", 0) or 0
    local customH = chat.Get("height", 0) or 0

    if not pos and customW <= 0 and customH <= 0 then
        -- Non-intrusive default: keep Blizzard native placement & size until customized.
        if CFD(cf1).bg then sync_panel_rect(cf1) end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        if sfui.safety and sfui.safety.DeferOutOfCombat then
            sfui.safety.DeferOutOfCombat("chat_apply_position", sfui.safety.OOC_P1, chat.ApplyChatPosition)
        end
        return
    end

    apply_cf1_anchors(cf1, pos, customW, customH)
    local d = CFD(cf1)
    d._pl = nil
    if d.bg then
        sync_panel_rect(cf1)
    end
    apply_editbox_position(cf1)
    if chat.RefreshTabs then chat.RefreshTabs() end
end

function chat.SyncMoverSize()
    if not (sfui.movers and sfui.movers.list and sfui.movers.list.chat and mainPanel) then return end
    local w = mainPanel:GetWidth()
    local h = mainPanel:GetHeight()
    if w and h and not issecretvalue(w) and not issecretvalue(h) and w > 0 and h > 0 then
        sfui.movers.list.chat:SetSize(w, h)
    end
end

function chat.ResetChatPosition()
    if InCombatLockdown and InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot reset chat position during combat lockdown.")
        end
        return
    end
    chat.Set("position", nil)
    chat.Set("width", 0)
    chat.Set("height", 0)
    local cf1 = _G.ChatFrame1
    if cf1 then
        local cfScale = (cf1.GetEffectiveScale and cf1:GetEffectiveScale()) or 1
        local uiScale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        local invK = (cfScale > 0) and (uiScale / cfScale) or 1
        rawClearAllPoints(cf1)
        rawSetPoint(cf1, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32 * invK, 50 * invK)
        rawSetPoint(cf1, "TOPRIGHT", UIParent, "BOTTOMLEFT", (32 + 414) * invK, (50 + 194) * invK)
        local d = CFD(cf1)
        local pl, pb, pr, pt = 32 - PAD.l, 50 - PAD.b, 32 + 414 + PAD.r, 50 + 194 + PAD.t
        d._pl, d._pb, d._pr, d._pt = pl, pb, pr, pt
        if d.bg then
            d.bg:ClearAllPoints()
            d.bg:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pl, pt)
            d.bg:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", pr, pb)
        end
        apply_editbox_position(cf1)
    end
    chat.SyncMoverSize()
    if chat.RefreshTabs then chat.RefreshTabs() end
end

function chat.RegisterMover()
    if not (sfui.movers and sfui.movers.Register and mainPanel) then return end
    sfui.movers.Register(mainPanel, {
        key = "chat",
        label = "chat",
        preferredPoint = "BOTTOMLEFT",
        isEnabled = function()
            return sfui.IsModuleEnabled("chat")
        end,
        customSize = function()
            local w = mainPanel and mainPanel:GetWidth()
            local h = mainPanel and mainPanel:GetHeight()
            if w and h and not issecretvalue(w) and not issecretvalue(h) and w > 0 and h > 0 then
                return w, h
            end
            return 430, 208
        end,
        getPoint = function()
            local pos = chat.Get("position", nil)
            if type(pos) == "table" and pos.point then
                return pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0
            end
            local cf1 = _G.ChatFrame1
            local d = cf1 and CFD(cf1)
            if d and d._pl ~= nil and d._pb ~= nil then
                return "BOTTOMLEFT", UIParent, "BOTTOMLEFT", math_floor(d._pl + 0.5), math_floor(d._pb + 0.5)
            end
            if mainPanel then
                local l = mainPanel:GetLeft()
                local b = mainPanel:GetBottom()
                if l and b and not issecretvalue(l) and not issecretvalue(b) then
                    return "BOTTOMLEFT", UIParent, "BOTTOMLEFT", math_floor(l + 0.5), math_floor(b + 0.5)
                end
            end
            return "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 42
        end,
        setPoint = function(point, _, relPoint, offsetX, offsetY)
            chat.Set("position", {
                point = point or "BOTTOMLEFT",
                relPoint = relPoint or point or "BOTTOMLEFT",
                x = math_floor((tonumber(offsetX) or 0) + 0.5),
                y = math_floor((tonumber(offsetY) or 0) + 0.5),
            })
            chat.ApplyChatPosition()
        end,
        resetPosition = function()
            chat.ResetChatPosition()
        end,
        onEnterEditMode = function()
            chat.WakeIdleFade()
            chat.WakeTabFade()
        end,
        onExitEditMode = function()
            chat.ScheduleRefresh()
        end,
    })
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Theme Refresh, Frame Refresh & Enable / Disable Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────

function chat.ApplyFrameTheme()
    local colors = chat.GetColors()
    chat.ForEachChatFrame(function(cf)
        local d = CFD(cf)
        if d.bg then
            style_panel_bg(d.bg, d)
        end
        if d.scrollThumb then
            d.scrollThumb:SetColorTexture(colors.scrollThumb[1], colors.scrollThumb[2], colors.scrollThumb[3], colors.scrollThumb[4])
        end
        local eb = get_editbox(cf)
        if eb and d.ebBg then
            local focused = is_editbox_focused(eb)
            d.ebBg:SetShown(focused or ((eb.IsShown and eb:IsShown() and has_unsent_text(eb)) and true or false))
            update_editbox_visuals(eb, focused)
        end
    end)
    style_corner_buttons()
end

function chat.ApplyEditBoxPositions()
    chat.ForEachChatFrame(function(cf)
        apply_editbox_position(cf)
    end)
end

function chat.RefreshScrollbars()
    chat.ForEachChatFrame(function(cf)
        apply_scrollbar_mode(cf)
        update_scrollbar(cf)
    end)
end

function chat.RefreshFrame()
    if not sfui.IsModuleEnabled("chat") then return end
    chat.ForEachChatFrame(function(cf)
        local d = CFD(cf)
        strip_chat_chrome(cf, d)
        local bg = ensure_panel(cf, d)
        sync_panel_strata_level(cf, bg)
        sync_panel_rect(cf)
        sync_panel_visibility(cf, d)
        ensure_scrollbar(cf, d)
        update_scrollbar(cf)
        ensure_wheel_boost(cf, d)
        skin_editbox(cf, d)
        apply_font_to_frame(cf, d)
        if cf == _G.ChatFrame1 then
            ensure_corner_buttons(bg)
        end
    end)

    if _G.QuickJoinToastButton then
        _G.QuickJoinToastButton:SetAlpha(0)
        if _G.QuickJoinToastButton.EnableMouse then
            _G.QuickJoinToastButton:EnableMouse(false)
        end
    end

    update_corner_buttons()
    chat.SyncMoverSize()
end

function chat.EnableFrame()
    if frameEnabled then return end
    frameEnabled = true
    register_editbox_callbacks()
    chat.WakeIdleFade()
    chat.WakeTabFade()
    chat.RefreshFrame()
    sync_chrome_tick_registration()
end

function chat.DisableFrame()
    frameEnabled = false
    unregister_editbox_callbacks()
    if sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate(CHROME_UPDATE_KEY)
    end

    chat.ForEachChatFrame(function(cf)
        local d = CFD(cf)
        if d.bg then
            if sfui.theme and sfui.theme.ClearFrameThemeLayers then
                sfui.theme.ClearFrameThemeLayers(d.bg)
            end
            d.bg:Hide()
        end
        if d.scrollTrack then d.scrollTrack:Hide() end
        restore_editbox(cf, d)
        restore_chat_chrome(cf, d)
        apply_font_to_frame(cf, d)
    end)

    if copyBtn then copyBtn:Hide() end
    if scrollBtn then scrollBtn:Hide() end
    if _G.QuickJoinToastButton then
        _G.QuickJoinToastButton:SetAlpha(1)
        if _G.QuickJoinToastButton.EnableMouse then
            _G.QuickJoinToastButton:EnableMouse(true)
        end
    end
end
