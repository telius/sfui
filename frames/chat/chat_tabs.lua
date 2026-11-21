local addonName, addon = ...
sfui = sfui or {}
sfui.chat = sfui.chat or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/chat/chat_tabs.lua
--  Zero-taint flat ghost tabs over Blizzard's live GeneralDockManager.
--  Blizzard tabs remain real, clickable, draggable & secure under alpha 0;
--  all custom visuals live on mouse-transparent UIParent-parented ghosts.
-- ══════════════════════════════════════════════════════════════════════════════

local chat = sfui.chat
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local pairs = _G.pairs
local type = _G.type
local math_max = math.max

local issecretvalue = chat.issecretvalue
local CFD = chat.CFD

local TAB_HEIGHT = 22
local GLOW_TEX = "Interface\\ChatFrame\\ChatFrameTab-NewMessage"

local strip = nil
local dynClip = nil
local dynClipAnchored = false
local ghosts = {}
local floatGhosts = {}
local floatSeen = {}
local origQuickBarParent = nil
local tabsEnabled = false
local lastTabAlpha = 1.0
local hasAlertingTab = false

local function is_frame_hovered(f)
    if not (f and f.IsShown and f:IsShown() and _G.MouseIsOver) then return false end
    local ok = _G.MouseIsOver(f)
    if issecretvalue(ok) then return false end
    return ok and true or false
end

local function is_tab_alerting(tab)
    if not tab then return false end
    if tab.alerting then return true end
    local util = _G.ChatFrameUtil
    if util and util.IsTabAlerting and util.IsTabAlerting(tab) then
        return true
    end
    return false
end

local function disable_mouse(f)
    if not f then return end
    if f.EnableMouse then f:EnableMouse(false) end
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(false) end
end

local function ensure_strip()
    if strip then return strip end
    strip = CreateFrame("Frame", "SfuiChatTabStrip", UIParent)
    strip:SetFrameStrata("MEDIUM")
    strip:SetFrameLevel(15)
    strip:SetClipsChildren(true)
    strip:SetAlpha(lastTabAlpha)
    disable_mouse(strip)
    strip:Hide()

    dynClip = CreateFrame("Frame", nil, strip)
    dynClip:SetClipsChildren(true)
    disable_mouse(dynClip)

    return strip
end

local function ensure_dyn_clip()
    if dynClipAnchored then return true end
    local dock = _G.GENERAL_CHAT_DOCK
    local sf = dock and dock.scrollFrame
    if not (sf and dynClip and strip) then return false end
    dynClip:ClearAllPoints()
    dynClip:SetPoint("TOP", strip, "TOP", 0, 0)
    dynClip:SetPoint("BOTTOM", strip, "BOTTOM", 0, 0)
    dynClip:SetPoint("LEFT", sf, "LEFT", 0, 0)
    dynClip:SetPoint("RIGHT", sf, "RIGHT", 0, 0)
    dynClipAnchored = true
    return true
end

local function create_ghost(parent)
    local g = CreateFrame("Frame", nil, parent or strip, "BackdropTemplate")
    g._sfuiPassThroughMouse = true
    disable_mouse(g)
    if sfui.widgets and sfui.widgets.set_pixel_snapping then
        sfui.widgets.set_pixel_snapping(g)
    end
    if sfui.widgets and sfui.widgets.apply_flat_backdrop then
        sfui.widgets.apply_flat_backdrop(g, { 0.04, 0.04, 0.05, 0.5 }, { 0, 0, 0, 0.85 })
    elseif g.SetBackdrop then
        g:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
    end

    local fs = g:CreateFontString(nil, "OVERLAY")
    local fontFile = sfui.common.get_font_file()
    fs:SetFont(fontFile, 11, "")
    fs:SetWordWrap(false)
    fs:SetJustifyH("CENTER")
    fs:SetPoint("LEFT", g, "LEFT", 6, 0)
    fs:SetPoint("RIGHT", g, "RIGHT", -6, 0)
    g._fs = fs
    g.fs = fs

    local underline = g:CreateTexture(nil, "OVERLAY", nil, 6)
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 1, 1)
    underline:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -1, 1)
    underline:Hide()
    g._underline = underline
    g.indicator = underline

    local glow = g:CreateTexture(nil, "OVERLAY", nil, 5)
    glow:SetTexture(GLOW_TEX)
    glow:SetBlendMode("ADD")
    if glow.SetDesaturated then glow:SetDesaturated(true) end
    glow:SetPoint("TOPLEFT", g, "TOPLEFT", 2, -2)
    glow:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -2, 2)
    glow:Hide()
    g._glow = glow

    if glow.CreateAnimationGroup then
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(0.25)
        a:SetToAlpha(0.80)
        a:SetDuration(0.5)
        g._flasher = ag
    end

    g._state = {}
    return g
end

local function set_ghost_flash(g, alerting)
    if not g._glow then return end
    if alerting then
        g._glow:Show()
        if g._flasher and not g._flasher:IsPlaying() then
            g._flasher:Play()
        end
    else
        if g._flasher and g._flasher:IsPlaying() then
            g._flasher:Stop()
        end
        g._glow:Hide()
    end
end

local function set_ghost_label(g, cf, isTemp)
    local fs = g._fs
    if isTemp then
        local label = cf.chatTarget
        if issecretvalue(label) then
            -- Direct forwarding to FontString: never compare, inspect, or transform secret names.
            fs:SetText(label)
        elseif label ~= nil then
            fs:SetText(label)
        else
            fs:SetText("...")
        end
    else
        local id = (cf.GetID and cf:GetID()) or 1
        local name = _G.GetChatWindowInfo and _G.GetChatWindowInfo(id)
        if name and not issecretvalue(name) and type(name) == "string" and name ~= "" then
            fs:SetText(name:lower())
        else
            fs:SetText("window " .. id)
        end
    end
end

local function style_ghost(g, cf, isActive, isTemp)
    local colors = chat.GetColors()
    local useTheme = chat.Get("use_theme", true) == true

    if useTheme and sfui.theme and sfui.theme.ApplyTabStyle then
        sfui.theme.ApplyTabStyle(g, isActive)
        if isTemp and _G.ChatTypeInfo then
            local ct = cf.chatType
            local info = (ct and not issecretvalue(ct) and _G.ChatTypeInfo[ct]) or _G.ChatTypeInfo["WHISPER"]
            if info and info.r and info.g and info.b then
                g._fs:SetTextColor(info.r, info.g, info.b, 1)
            end
        end
    else
        if sfui.theme and sfui.theme.ClearFrameThemeLayers then
            sfui.theme.ClearFrameThemeLayers(g)
        end
        local bg = isActive and colors.tabActiveBg or colors.tabBg
        if sfui.widgets and sfui.widgets.apply_flat_backdrop then
            sfui.widgets.apply_flat_backdrop(g, { bg[1], bg[2], bg[3], bg[4] or 0.7 }, { 0, 0, 0, 0.85 })
        elseif g.SetBackdropColor then
            g:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.7)
            if g.SetBackdropBorderColor then
                g:SetBackdropBorderColor(0, 0, 0, 0.85)
            end
        end

        local tr, tg, tb, ta
        if isTemp and _G.ChatTypeInfo then
            local ct = cf.chatType
            local info = (ct and not issecretvalue(ct) and _G.ChatTypeInfo[ct]) or _G.ChatTypeInfo["WHISPER"]
            if info and info.r and info.g and info.b then
                tr, tg, tb, ta = info.r, info.g, info.b, 1
            end
        end
        if not tr then
            local tc = isActive and colors.tabActiveText or colors.tabText
            tr, tg, tb, ta = tc[1], tc[2], tc[3], tc[4] or 1
        end
        g._fs:SetTextColor(tr, tg, tb, ta)
        g._fs:SetShadowOffset(0, 0)

        if isActive then
            g._underline:SetColorTexture(colors.accent[1], colors.accent[2], colors.accent[3], colors.accent[4] or 1)
            g._underline:Show()
        else
            g._underline:Hide()
        end
    end

    if g._glow then
        g._glow:SetVertexColor(colors.accent[1], colors.accent[2], colors.accent[3])
    end
end

local function suppress_undocked_tab(tab, suppress)
    if not (tab and tab.GetRegions) then return end
    local td = CFD(tab)
    local regions = { tab:GetRegions() }
    if suppress then
        if not td.savedRegionAlphas then td.savedRegionAlphas = {} end
        for i = 1, #regions do
            local r = regions[i]
            if r and r.SetAlpha then
                local a = r.GetAlpha and r:GetAlpha()
                if td.savedRegionAlphas[r] == nil and a ~= nil and not issecretvalue(a) then
                    td.savedRegionAlphas[r] = a
                end
                if issecretvalue(a) or a ~= 0 then
                    r:SetAlpha(0)
                end
            end
        end
        td.suppressed = true
    elseif td.suppressed then
        td.suppressed = nil
        for i = 1, #regions do
            local r = regions[i]
            if r and r.SetAlpha then
                local saved = td.savedRegionAlphas and td.savedRegionAlphas[r]
                r:SetAlpha(saved ~= nil and saved or 1)
            end
        end
    end
end

local function sync_blizzard_dock_alpha(wantGhost)
    local gdm = _G.GeneralDockManager
    if gdm then
        if wantGhost then
            local a = gdm.GetAlpha and gdm:GetAlpha()
            if (a ~= nil and issecretvalue(a)) or a ~= 0 then
                gdm:SetAlpha(0)
            end
            local ob = gdm.overflowButton
            if ob then
                if ob.SetIgnoreParentAlpha and not ob:IsIgnoringParentAlpha() then
                    ob:SetIgnoreParentAlpha(true)
                end
                local list = ob.list
                if list and list.SetIgnoreParentAlpha and not list:IsIgnoringParentAlpha() then
                    list:SetIgnoreParentAlpha(true)
                end
            end
            local qb = _G.CombatLogQuickButtonFrame_Custom
            local cf2 = _G.ChatFrame2
            if qb then
                if qb.SetIgnoreParentAlpha then
                    qb:SetIgnoreParentAlpha(true)
                end
                if cf2 and qb:GetParent() ~= cf2 and not (InCombatLockdown and InCombatLockdown()) then
                    if origQuickBarParent == nil then
                        origQuickBarParent = qb:GetParent()
                    end
                    qb:SetParent(cf2)
                end
            end
        else
            gdm:SetAlpha(1)
            local qb = _G.CombatLogQuickButtonFrame_Custom
            if qb then
                if qb.SetIgnoreParentAlpha then
                    qb:SetIgnoreParentAlpha(false)
                end
                if origQuickBarParent and qb:GetParent() ~= origQuickBarParent and not (InCombatLockdown and InCombatLockdown()) then
                    qb:SetParent(origQuickBarParent)
                end
            end
        end
    end

    chat.ForEachChatFrame(function(cf)
        local name = cf.GetName and cf:GetName()
        local tab = name and _G[name .. "Tab"]
        if tab then
            if wantGhost and not cf.isDocked then
                suppress_undocked_tab(tab, true)
            else
                suppress_undocked_tab(tab, false)
            end
        end
    end)
end

local function position_strip()
    local gdm = _G.GeneralDockManager
    if not (strip and gdm) then return end

    local leftExtend = 0
    local mainPanel = chat.GetMainPanel and chat.GetMainPanel()
    local dockList = _G.GENERAL_CHAT_DOCK and _G.GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    local firstCF = type(dockList) == "table" and dockList[1]
    local firstName = firstCF and firstCF.GetName and firstCF:GetName()
    local firstTab = firstName and _G[firstName .. "Tab"]

    local bgL = mainPanel and mainPanel.GetLeft and mainPanel:GetLeft()
    local tabL = firstTab and firstTab.GetLeft and firstTab:GetLeft()
    if bgL and tabL and not issecretvalue(bgL) and not issecretvalue(tabL) then
        local delta = bgL - tabL
        if delta < 0 and delta > -32 then
            leftExtend = delta
        end
    end

    strip:SetFrameStrata((gdm.GetFrameStrata and gdm:GetFrameStrata()) or "MEDIUM")
    strip:SetFrameLevel(math_max(1, (gdm.GetFrameLevel and gdm:GetFrameLevel()) or 1))
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", gdm, "TOPLEFT", leftExtend - 2, 2)
    strip:SetPoint("BOTTOMRIGHT", gdm, "BOTTOMRIGHT", 2, -2)
    strip:Show()
    return leftExtend
end

function chat.GetTabStrip()
    return strip
end

function chat.HasAlertingTab()
    return hasAlertingTab
end

function chat.IsFloatingHovered()
    for _, g in pairs(floatGhosts) do
        if g and g:IsShown() then
            if is_frame_hovered(g) then return true end
            local st = g._state
            local d = st and st.cf and CFD(st.cf)
            if d and is_frame_hovered(d.bg) then return true end
        end
    end
    return false
end

function chat.SetTabStripAlpha(alpha)
    lastTabAlpha = alpha
    if strip then strip:SetAlpha(alpha) end
    for _, g in pairs(floatGhosts) do
        if g then g:SetAlpha(alpha) end
    end
end

function chat.ApplyTabTheme()
    for i = 1, #ghosts do
        local g = ghosts[i]
        if g and g:IsShown() and g._state and g._state.cf then
            style_ghost(g, g._state.cf, g._state.isActive, g._state.isTemp)
        end
    end
    for _, g in pairs(floatGhosts) do
        if g and g:IsShown() and g._state and g._state.cf then
            style_ghost(g, g._state.cf, g._state.isActive, g._state.isTemp)
        end
    end
end

function chat.RefreshTabs()
    if not tabsEnabled then return end
    local wantGhost = sfui.IsModuleEnabled("chat") and (chat.Get("ghost_tabs", true) == true)
    sync_blizzard_dock_alpha(wantGhost)

    if not wantGhost then
        hasAlertingTab = false
        if strip then strip:Hide() end
        for i = 1, #ghosts do
            set_ghost_flash(ghosts[i], false)
            ghosts[i]:Hide()
        end
        for _, g in pairs(floatGhosts) do
            set_ghost_flash(g, false)
            g:Hide()
        end
        return
    end

    ensure_strip()
    strip:SetAlpha(lastTabAlpha)
    local leftExtend = position_strip() or 0

    local dock = _G.GENERAL_CHAT_DOCK
    local dockList = dock and dock.DOCKED_CHAT_FRAMES
    local selected = chat.GetActiveChatFrame()
    local scrollFrame = dock and dock.scrollFrame
    local scrollChild = scrollFrame and scrollFrame.GetScrollChild and scrollFrame:GetScrollChild() or nil

    local count = 0
    local anyAlerting = false
    if type(dockList) == "table" then
        for i = 1, #dockList do
            local cf = dockList[i]
            local name = cf and cf.GetName and cf:GetName()
            local tab = name and _G[name .. "Tab"]
            if tab then
                count = count + 1
                local g = ghosts[count]
                if not g then
                    g = create_ghost(strip)
                    ghosts[count] = g
                end

                local isTemp = (cf.isTemporary and true) or false
                local isActive = (cf == selected)
                g._state.cf = cf
                g._state.isTemp = isTemp
                g._state.isActive = isActive

                local wantParent = strip
                local isScrolling = scrollChild and (tab:GetParent() == scrollChild)
                if isScrolling and ensure_dyn_clip() then
                    wantParent = dynClip
                end
                if g:GetParent() ~= wantParent then
                    g:SetParent(wantParent)
                end

                local leftOffset = (count == 1 and leftExtend ~= 0) and leftExtend or 0
                g:ClearAllPoints()
                g:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", leftOffset, 0)
                g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -1, 0)
                g:SetHeight(TAB_HEIGHT)

                local alerting = (not isActive) and is_tab_alerting(tab)
                if alerting then anyAlerting = true end
                set_ghost_label(g, cf, isTemp)
                style_ghost(g, cf, isActive, isTemp)
                set_ghost_flash(g, alerting)
                g:Show()
            end
        end
    end

    for i = count + 1, #ghosts do
        local g = ghosts[i]
        g._state.cf = nil
        set_ghost_flash(g, false)
        g:Hide()
    end

    -- Float ghosts for shown undocked chat windows
    for k in pairs(floatSeen) do floatSeen[k] = nil end
    chat.ForEachChatFrame(function(cf, id)
        if not cf.isDocked and cf:IsShown() then
            local name = cf.GetName and cf:GetName()
            local tab = name and _G[name .. "Tab"]
            local d = CFD(cf)
            if tab and d and d.bg then
                local g = floatGhosts[id]
                if not g then
                    g = create_ghost(d.bg)
                    floatGhosts[id] = g
                elseif g:GetParent() ~= d.bg then
                    g:SetParent(d.bg)
                end
                g:SetFrameStrata("MEDIUM")
                g:SetFrameLevel(math_max(10, (d.bg:GetFrameLevel() or 5) + 5))

                local isTemp = (cf.isTemporary and true) or false
                g._state.cf = cf
                g._state.isTemp = isTemp
                g._state.isActive = true

                g:ClearAllPoints()
                g:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                g:SetHeight(TAB_HEIGHT)

                set_ghost_label(g, cf, isTemp)
                style_ghost(g, cf, true, isTemp)
                set_ghost_flash(g, false)
                g:SetAlpha(lastTabAlpha)
                g:Show()
                floatSeen[id] = true
            end
        end
    end)

    for id, g in pairs(floatGhosts) do
        if not floatSeen[id] then
            g._state.cf = nil
            set_ghost_flash(g, false)
            g:Hide()
        end
    end

    hasAlertingTab = anyAlerting
    if anyAlerting and chat.WakeTabFade then
        chat.WakeTabFade()
    end
end

function chat.EnableTabs()
    if tabsEnabled then return end
    tabsEnabled = true
    chat.RefreshTabs()
end

function chat.DisableTabs()
    tabsEnabled = false
    hasAlertingTab = false
    lastTabAlpha = 1.0
    sync_blizzard_dock_alpha(false)
    if strip then
        strip:SetAlpha(1.0)
        strip:Hide()
    end
    for i = 1, #ghosts do
        set_ghost_flash(ghosts[i], false)
        ghosts[i]:Hide()
    end
    for _, g in pairs(floatGhosts) do
        set_ghost_flash(g, false)
        g:SetAlpha(1.0)
        g:Hide()
    end
end
