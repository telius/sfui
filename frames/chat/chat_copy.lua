local addonName, addon = ...
sfui = sfui or {}
sfui.chat = sfui.chat or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/chat/chat_copy.lua
--  On-demand chat copy popup, clickable URL wrapping + quick copy box, and
--  hyperlink hover tooltips via EventRegistry (secret-value & taint safe).
-- ══════════════════════════════════════════════════════════════════════════════

local chat = sfui.chat
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Timer = _G.C_Timer
local GetCursorPosition = _G.GetCursorPosition
local IsControlKeyDown = _G.IsControlKeyDown
local hooksecurefunc = _G.hooksecurefunc
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local tostring = _G.tostring
local table_concat = table.concat
local string_format = string.format

local issecretvalue = chat.issecretvalue
local LINKS_OWNER = "sfui_chat_links"

local URL_MESSAGE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_SYSTEM",
}

local TOOLTIP_LINK_TYPES = {
    achievement  = true,
    apower       = true,
    azessence    = true,
    battlepet    = true,
    conduit      = true,
    currency     = true,
    enchant      = true,
    glyph        = true,
    instancelock = true,
    item         = true,
    keystone     = true,
    mawpower     = true,
    mount        = true,
    quest        = true,
    spell        = true,
    talent       = true,
    unit         = true,
}

local copyFrame = nil
local urlFrame = nil
local currentCopyTarget = nil
local currentText = ""
local filtersInstalled = false
local setItemRefHooked = false
local hoverCallbacksRegistered = false
local hyperlinkEnteredFrame = nil
local eraHyperlinkHooked = {}

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

-- ─────────────────────────────────────────────────────────────────────────────
--  Chat Buffer Extraction & UI Escape Stripping
-- ─────────────────────────────────────────────────────────────────────────────

local PIPE_GUARD = "\001SFUIPIPE\002"

function chat.CleanChatLine(text, keepColors)
    if text == nil or issecretvalue(text) or type(text) ~= "string" then
        return nil
    end

    text = text:gsub("||", PIPE_GUARD)
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|n", "\n")

    if not keepColors then
        text = text:gsub("|cn[^:]+:", "")
        text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
        text = text:gsub("|r", "")
    end

    text = text:gsub(PIPE_GUARD, "|")
    return text
end

function chat.ReadChatLines(cf, keepColors)
    cf = cf or (chat.GetActiveChatFrame and chat.GetActiveChatFrame()) or _G.ChatFrame1
    if not (cf and cf.GetNumMessages and cf.GetMessageInfo) then
        return "", 0, 0
    end

    local total = cf:GetNumMessages()
    if issecretvalue(total) or type(total) ~= "number" or total <= 0 then
        return "", 0, 0
    end

    local out = {}
    local skippedSecret = 0
    for i = 1, total do
        local raw = cf:GetMessageInfo(i)
        if issecretvalue(raw) then
            skippedSecret = skippedSecret + 1
        elseif raw ~= nil and type(raw) == "string" then
            local cleaned = chat.CleanChatLine(raw, keepColors)
            if cleaned and cleaned ~= "" then
                out[#out + 1] = cleaned
            end
        end
    end

    return table_concat(out, "\n"), #out, skippedSecret
end

-- ─────────────────────────────────────────────────────────────────────────────
--  URL Detection, Wrapping & Quick Copy Box
-- ─────────────────────────────────────────────────────────────────────────────

local function strip_trailing_punct(url)
    local clean, punct = url:match("^(.-)([%.,;:!%?]+)$")
    if clean and clean ~= "" then
        url = clean
    else
        punct = ""
    end
    -- Trim unmatched closing brackets/parens from the URL (e.g. "(https://example.com)").
    local tail = ""
    while url ~= "" do
        local last = url:sub(-1)
        if last == ")" then
            local _, openCount = url:gsub("%(", "")
            local _, closeCount = url:gsub("%)", "")
            if closeCount > openCount then
                url = url:sub(1, -2)
                tail = ")" .. tail
            else
                break
            end
        elseif last == "]" or last == "}" or last == ">" then
            url = url:sub(1, -2)
            tail = last .. tail
        else
            break
        end
    end
    if url == "" then
        return url .. tail .. punct, ""
    end
    return url, tail .. punct
end

local function wrap_url_token(url, subPrefix)
    local clean, tail = strip_trailing_punct(url)
    if clean == "" then return url end
    return "|cff" .. subPrefix .. "|Hsfuiurl:" .. clean .. "|h[" .. clean .. "]|h|r" .. tail
end

local ESCAPE_PATTERNS = {
    "|H.-|h.-|h",
    "|T.-|t",
    "|A.-|a",
    "|K.-|k",
    "|cn[^:]+:",
    "|c%x%x%x%x%x%x%x%x",
    "|r",
}

local function find_next_escape(text, pos)
    local bestS, bestE = nil, nil
    for i = 1, #ESCAPE_PATTERNS do
        local s, e = text:find(ESCAPE_PATTERNS[i], pos)
        if s and (not bestS or s < bestS) then
            bestS, bestE = s, e
        end
    end
    return bestS, bestE
end

local function map_plain_segments(text, fn)
    if not text:find("|", 1, true) then
        return fn(text)
    end
    local parts = {}
    local pos = 1
    local len = #text
    while pos <= len do
        local s, e = find_next_escape(text, pos)
        if not s then
            parts[#parts + 1] = fn(text:sub(pos))
            break
        end
        if s > pos then
            parts[#parts + 1] = fn(text:sub(pos, s - 1))
        end
        parts[#parts + 1] = text:sub(s, e)
        pos = e + 1
    end
    return table_concat(parts)
end

local function wrap_pattern_single_pass(seg, pat, subFn)
    return seg:gsub(pat, function(pos, u)
        if pos > 1 and not seg:sub(pos - 1, pos - 1):match("[%s%(%[%{<]") then
            return u
        end
        return subFn(u)
    end)
end

function chat.WrapURLs(text)
    if text == nil or issecretvalue(text) or type(text) ~= "string" then
        return text
    end
    local hasScheme = text:find("://", 1, true)
    local hasWww = text:find("www.", 1, true)
    if not (hasScheme or hasWww) then
        return text
    end

    local colors = chat.GetColors()
    local accentHex = colors.accentHex or "00d9f2"
    local function sub_fn(u)
        return wrap_url_token(u, accentHex)
    end

    if hasScheme then
        text = map_plain_segments(text, function(seg)
            if not seg:find("://", 1, true) then return seg end
            return wrap_pattern_single_pass(seg, "()(%a[%w%+%.%-]+://[^%s|]+)", sub_fn)
        end)
    end
    if hasWww then
        text = map_plain_segments(text, function(seg)
            if not seg:find("www.", 1, true) then return seg end
            return wrap_pattern_single_pass(seg, "()(www%.[%w_%-]+%.%a%a+[^%s|]*)", sub_fn)
        end)
    end

    return text
end

local function url_message_filter(_, _, msg, ...)
    if not sfui.IsModuleEnabled("chat") or not chat.Get("url_links", true) then
        return false, msg, ...
    end
    if issecretvalue(msg) or type(msg) ~= "string" then
        return false, msg, ...
    end
    if not (msg:find("://", 1, true) or msg:find("www.", 1, true)) then
        return false, msg, ...
    end
    return false, chat.WrapURLs(msg), ...
end

local function style_url_frame(useTheme, colors)
    if not urlFrame then return end
    if useTheme == nil then
        useTheme = chat.Get("use_theme", true) == true
    end
    colors = colors or chat.GetColors()
    local theme = sfui.theme
    if useTheme and theme then
        if theme.ApplyWindowStyle then
            theme.ApplyWindowStyle(urlFrame, { cornerBrackets = false, texturedBackdrop = false })
        end
        if urlFrame._eb and theme.ApplyInputStyle then
            theme.ApplyInputStyle(urlFrame._eb)
        end
    else
        if theme and theme.ClearFrameThemeLayers then
            theme.ClearFrameThemeLayers(urlFrame)
            if urlFrame._eb then
                theme.ClearFrameThemeLayers(urlFrame._eb)
            end
        end
        apply_flat(urlFrame, { colors.bg[1], colors.bg[2], colors.bg[3], 0.96 }, colors.accent)
        if urlFrame._eb then
            apply_flat(urlFrame._eb, colors.ebBg, colors.border)
        end
    end
end

local function show_url_popup(url)
    if not url or issecretvalue(url) or type(url) ~= "string" then return end
    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
    if not urlFrame then
        urlFrame = CreateFrame("Frame", "SfuiChatUrlFrame", UIParent, "BackdropTemplate")
        urlFrame:SetSize(340, 56)
        urlFrame:SetFrameStrata("DIALOG")
        urlFrame:SetFrameLevel(200)
        urlFrame:SetClampedToScreen(true)
        urlFrame:EnableMouse(true)

        if sfui.common and sfui.common.register_special_frame then
            sfui.common.register_special_frame("SfuiChatUrlFrame")
        end

        local hint = urlFrame:CreateFontString(nil, "OVERLAY")
        hint:SetFont(fontFile, 10, "")
        hint:SetTextColor(0.75, 0.75, 0.78, 1)
        hint:SetPoint("TOP", urlFrame, "TOP", 0, -6)
        hint:SetText("ctrl+c to copy, esc to close")

        local eb = CreateFrame("EditBox", nil, urlFrame, "BackdropTemplate")
        eb:SetSize(320, 22)
        eb:SetPoint("BOTTOM", urlFrame, "BOTTOM", 0, 8)
        eb:SetFont(fontFile, 11, "")
        eb:SetTextInsets(6, 6, 0, 0)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            urlFrame:Hide()
        end)
        eb:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown and IsControlKeyDown() and C_Timer and C_Timer.After then
                C_Timer.After(0.05, function()
                    if urlFrame then urlFrame:Hide() end
                end)
            end
        end)
        eb:SetScript("OnEditFocusLost", function()
            if urlFrame then urlFrame:Hide() end
        end)
        eb:SetScript("OnMouseUp", function(self)
            self:HighlightText()
        end)
        urlFrame._eb = eb
    end

    style_url_frame()
    urlFrame:ClearAllPoints()
    local cx, cy
    if GetCursorPosition then
        cx, cy = GetCursorPosition()
    end
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if cx and cy and not issecretvalue(cx) and not issecretvalue(cy) and scale > 0 then
        urlFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, (cy / scale) + 12)
    else
        urlFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end

    urlFrame._eb:SetText(url)
    urlFrame:Show()
    urlFrame._eb:SetFocus()
    urlFrame._eb:HighlightText()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Chat Copy Window
-- ─────────────────────────────────────────────────────────────────────────────

local function populate_copy_window(cf)
    if not copyFrame then return end
    cf = cf or currentCopyTarget or (chat.GetActiveChatFrame and chat.GetActiveChatFrame()) or _G.ChatFrame1
    currentCopyTarget = cf

    local keepColors = chat.Get("copy_keep_colors", false) == true
    local text, lineCount, skippedSecret = chat.ReadChatLines(cf, keepColors)
    currentText = (lineCount > 0 and text) or "no chat lines found"

    if copyFrame._title then
        local titleStr = "chat copy"
        if cf and not cf.isTemporary and cf.GetID and _G.GetChatWindowInfo then
            local name = _G.GetChatWindowInfo(cf:GetID())
            if name and not issecretvalue(name) and type(name) == "string" and name ~= "" then
                titleStr = "chat copy - " .. name:lower()
            end
        elseif cf and cf.isTemporary then
            local target = cf.chatTarget
            if target and not issecretvalue(target) and type(target) == "string" and target ~= "" then
                titleStr = "chat copy - " .. target:lower()
            else
                titleStr = "chat copy - whisper"
            end
        end
        copyFrame._title:SetText(titleStr)
    end

    if copyFrame._status then
        if skippedSecret > 0 then
            copyFrame._status:SetText(string_format("%d lines (%d restricted omitted) | ctrl+c to copy, esc to close", lineCount, skippedSecret))
        else
            copyFrame._status:SetText(string_format("%d lines | ctrl+c to copy, esc to close", lineCount))
        end
    end

    if copyFrame._scrollEdit then
        copyFrame._scrollEdit:SetText(currentText)
    elseif copyFrame._editBox then
        copyFrame._editBox:SetText(currentText)
    end

    local function focus_bottom()
        if not (copyFrame and copyFrame:IsShown()) then return end
        local eb = copyFrame._editBox
        if eb then
            eb:SetFocus()
            if eb.SetCursorPosition then eb:SetCursorPosition(#currentText) end
            if eb.HighlightText then eb:HighlightText() end
        end
        if copyFrame._scrollBox and copyFrame._scrollBox.ScrollToEnd then
            copyFrame._scrollBox:ScrollToEnd(true)
        elseif copyFrame._scrollFrame and copyFrame._scrollFrame.UpdateScrollChildRect then
            copyFrame._scrollFrame:UpdateScrollChildRect()
            local maxScroll = copyFrame._scrollFrame:GetVerticalScrollRange() or 0
            copyFrame._scrollFrame:SetVerticalScroll(maxScroll)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, focus_bottom)
    else
        focus_bottom()
    end
end

local function apply_copy_window_theme(useTheme, colors)
    if not copyFrame then return end
    local theme = sfui.theme
    if useTheme and theme then
        if theme.ApplyWindowStyle then
            theme.ApplyWindowStyle(copyFrame)
        end
        if copyFrame._boxBg and theme.ApplyContainerStyle then
            theme.ApplyContainerStyle(copyFrame._boxBg)
        end
        if copyFrame._scrollBar and theme.ApplyScrollBarStyle then
            theme.ApplyScrollBarStyle(copyFrame._scrollBar)
        end
        if copyFrame._title then
            local pal = theme.GetPalette and theme.GetPalette()
            local hc = (pal and pal.headerColor) or colors.tabActiveText
            copyFrame._title:SetTextColor(hc[1], hc[2], hc[3], 1)
        end
    else
        if theme and theme.ClearFrameThemeLayers then
            theme.ClearFrameThemeLayers(copyFrame)
            if copyFrame._boxBg then
                theme.ClearFrameThemeLayers(copyFrame._boxBg)
            end
            if copyFrame._scrollBar then
                theme.ClearFrameThemeLayers(copyFrame._scrollBar)
            end
        end
        apply_flat(copyFrame, { colors.bg[1], colors.bg[2], colors.bg[3], 0.94 }, colors.border)
        if copyFrame._boxBg then
            apply_flat(copyFrame._boxBg, { colors.ebBg[1], colors.ebBg[2], colors.ebBg[3], 0.92 }, colors.innerBorder)
        end
        if copyFrame._title then
            copyFrame._title:SetTextColor(colors.tabActiveText[1], colors.tabActiveText[2], colors.tabActiveText[3], 1)
        end
    end
end

function chat.ApplyCopyTheme()
    local colors = chat.GetColors()
    local useTheme = chat.Get("use_theme", true) == true
    apply_copy_window_theme(useTheme, colors)
    style_url_frame(useTheme, colors)
end

local function build_copy_window()
    if copyFrame then return copyFrame end
    local colors = chat.GetColors()
    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file()) or "Fonts\\FRIZQT__.TTF"

    local f = CreateFrame("Frame", "SfuiChatCopyFrame", UIParent, "BackdropTemplate")
    f:SetSize(560, 360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(150)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    apply_flat(f, { colors.bg[1], colors.bg[2], colors.bg[3], 0.94 }, colors.border)

    if sfui.common and sfui.common.register_special_frame then
        sfui.common.register_special_frame("SfuiChatCopyFrame")
    end

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontFile, 12, "")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetTextColor(colors.tabActiveText[1], colors.tabActiveText[2], colors.tabActiveText[3], 1)
    title:SetText("chat copy")
    f._title = title

    local closeBtn
    if sfui.widgets and sfui.widgets.create_close_button then
        closeBtn = sfui.widgets.create_close_button(f, function() f:Hide() end, 18)
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
        if not closeBtn.isThemedClose then
            closeBtn:SetText("x")
            local cfs = closeBtn:GetFontString()
            if cfs then cfs:SetText("x") end
        end
    else
        closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        closeBtn:SetSize(18, 18)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
        closeBtn:SetScript("OnClick", function() f:Hide() end)
    end

    local selectAllBtn
    if sfui.widgets and sfui.widgets.create_flat_button then
        selectAllBtn = sfui.widgets.create_flat_button(f, "select all", 72, 18, function()
            if f._editBox then
                f._editBox:SetFocus()
                f._editBox:HighlightText()
            end
        end)
    else
        selectAllBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        selectAllBtn:SetSize(72, 18)
    end
    selectAllBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)

    local colorsCb
    if sfui.widgets and sfui.widgets.create_checkbox then
        colorsCb = sfui.widgets.create_checkbox(f, "colors", function()
            return chat.Get("copy_keep_colors", false) == true
        end, function(checked)
            chat.Set("copy_keep_colors", checked and true or false)
            populate_copy_window(currentCopyTarget)
        end, "preserve wow color escape codes when copying chat.")
        colorsCb:SetSize(16, 16)
        colorsCb:SetPoint("RIGHT", selectAllBtn, "LEFT", -56, 0)
        if colorsCb.text then
            colorsCb.text:SetFont(fontFile, 11, "")
        end
    end

    local boxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    boxBg:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    boxBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 26)
    apply_flat(boxBg, { colors.ebBg[1], colors.ebBg[2], colors.ebBg[3], 0.92 }, colors.innerBorder)
    f._boxBg = boxBg

    local function bind_readonly_keys(eb)
        if eb.SetMaxLetters then eb:SetMaxLetters(0) end
        if eb.SetAutoFocus then eb:SetAutoFocus(false) end
        if eb.SetFont then eb:SetFont(fontFile, 12, "") end
        if eb.SetTextColor then eb:SetTextColor(0.92, 0.92, 0.94, 1) end
        if eb.HookScript then
            eb:HookScript("OnChar", function(self)
                if self._sfuiCopying then return end
                self._sfuiCopying = true
                self:SetText(currentText)
                self:HighlightText()
                self._sfuiCopying = nil
            end)
        end
    end

    if _G.ScrollingEditBoxMixin then
        local scrollEdit = CreateFrame("Frame", nil, boxBg, "ScrollingEditBoxTemplate")
        scrollEdit:SetPoint("TOPLEFT", boxBg, "TOPLEFT", 6, -6)
        scrollEdit:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -20, 6)
        f._scrollEdit = scrollEdit
        f._scrollBox = scrollEdit:GetScrollBox()
        local eb = scrollEdit:GetEditBox()
        f._editBox = eb
        bind_readonly_keys(eb)

        if scrollEdit.RegisterCallback then
            scrollEdit:RegisterCallback("OnEscapePressed", function()
                f:Hide()
            end)
            scrollEdit:RegisterCallback("OnKeyDown", function(_, _, key)
                if key == "C" and IsControlKeyDown and IsControlKeyDown() and C_Timer and C_Timer.After then
                    C_Timer.After(0.05, function() f:Hide() end)
                end
            end)
        end

        if _G.ScrollUtil and _G.ScrollUtil.InitScrollBar and _G.MinimalScrollBar then
            local sb = CreateFrame("EventFrame", nil, boxBg, "MinimalScrollBar")
            sb:SetPoint("TOPRIGHT", boxBg, "TOPRIGHT", -4, -6)
            sb:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -4, 6)
            _G.ScrollUtil.InitScrollBar(f._scrollBox, sb)
            f._scrollBar = sb
        end
    else
        local sf, sc = sfui.widgets.create_scroll_frame(boxBg, nil, 510, 260)
        sf:SetPoint("TOPLEFT", boxBg, "TOPLEFT", 6, -6)
        sf:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -20, 6)
        local eb = CreateFrame("EditBox", nil, sc)
        eb:SetMultiLine(true)
        eb:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
        eb:SetWidth(504)
        bind_readonly_keys(eb)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown and IsControlKeyDown() and C_Timer and C_Timer.After then
                C_Timer.After(0.05, function() f:Hide() end)
            end
        end)
        eb:SetScript("OnTextChanged", function(self)
            local h = math_max(260, (self:GetStringHeight() or 260) + 20)
            sc:SetHeight(h)
        end)
        f._scrollFrame = sf
        f._editBox = eb
    end

    local status = f:CreateFontString(nil, "OVERLAY")
    status:SetFont(fontFile, 10, "")
    status:SetTextColor(0.65, 0.65, 0.68, 1)
    status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    status:SetText("press ctrl+c to copy, esc to close")
    f._status = status

    f:SetScript("OnHide", function()
        if colorsCb and colorsCb.SetChecked then
            colorsCb:SetChecked(chat.Get("copy_keep_colors", false) == true)
        end
    end)

    f:Hide()
    copyFrame = f
    chat.ApplyCopyTheme()
    return f
end

function chat.OpenCopyWindow(cf)
    if not sfui.IsModuleEnabled("chat") then
        if sfui.common and sfui.common.print then
            sfui.common.print("chat module is disabled.")
        end
        return
    end
    build_copy_window()
    populate_copy_window(cf)
    copyFrame:Show()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hyperlink Hover Tooltips
-- ─────────────────────────────────────────────────────────────────────────────

local function handle_hyperlink_enter(cf, link)
    if not sfui.IsModuleEnabled("chat") or not chat.Get("hover_tooltips", true) then
        return
    end
    if not link or issecretvalue(link) or type(link) ~= "string" then
        return
    end
    local linkType = link:match("^([^:]+)")
    if not (linkType and TOOLTIP_LINK_TYPES[linkType]) then
        return
    end
    local tip = _G.GameTooltip
    if not tip then return end
    tip:SetOwner(cf or UIParent, "ANCHOR_CURSOR")
    if tip.SetHyperlink then
        tip:SetHyperlink(link)
    end
    tip:Show()
    hyperlinkEnteredFrame = cf or true
end

local function handle_hyperlink_leave()
    if hyperlinkEnteredFrame then
        hyperlinkEnteredFrame = nil
        local tip = _G.GameTooltip
        if tip then tip:Hide() end
    end
end

local function register_hover_callbacks()
    if hoverCallbacksRegistered then return end
    local ER = _G.EventRegistry
    if ER and ER.RegisterCallback and not sfui.isEra then
        hoverCallbacksRegistered = true
        ER:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, cf, link)
            handle_hyperlink_enter(cf, link)
        end, LINKS_OWNER)
        ER:RegisterCallback("ChatFrame.OnHyperlinkLeave", function()
            handle_hyperlink_leave()
        end, LINKS_OWNER)
    else
        chat.ForEachChatFrame(function(cf)
            if not eraHyperlinkHooked[cf] and not cf.isTemporary and cf.HookScript then
                eraHyperlinkHooked[cf] = true
                cf:HookScript("OnHyperlinkEnter", handle_hyperlink_enter)
                cf:HookScript("OnHyperlinkLeave", handle_hyperlink_leave)
            end
        end)
    end
end

local function unregister_hover_callbacks()
    handle_hyperlink_leave()
    if not hoverCallbacksRegistered then return end
    hoverCallbacksRegistered = false
    local ER = _G.EventRegistry
    if ER and ER.UnregisterCallback then
        ER:UnregisterCallback("ChatFrame.OnHyperlinkEnter", LINKS_OWNER)
        ER:UnregisterCallback("ChatFrame.OnHyperlinkLeave", LINKS_OWNER)
    end
end

local function install_url_hooks()
    if not filtersInstalled then
        filtersInstalled = true
        local addFilter = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
        if addFilter then
            for i = 1, #URL_MESSAGE_EVENTS do
                addFilter(URL_MESSAGE_EVENTS[i], url_message_filter)
            end
        end
    end
    if not setItemRefHooked and hooksecurefunc and _G.SetItemRef then
        setItemRefHooked = true
        hooksecurefunc("SetItemRef", function(link)
            if not sfui.IsModuleEnabled("chat") or not chat.Get("url_links", true) then
                return
            end
            if not link or issecretvalue(link) or type(link) ~= "string" then
                return
            end
            local url = link:match("^sfuiurl:(.+)$")
            if url then
                show_url_popup(url)
            end
        end)
    end
end

function chat.RefreshCopyHooks()
    if not sfui.IsModuleEnabled("chat") then return end
    if chat.Get("hover_tooltips", true) then
        register_hover_callbacks()
    else
        unregister_hover_callbacks()
    end
end

function chat.EnableCopy()
    install_url_hooks()
    chat.RefreshCopyHooks()
end

function chat.DisableCopy()
    unregister_hover_callbacks()
    if copyFrame then copyFrame:Hide() end
    if urlFrame then urlFrame:Hide() end
end
