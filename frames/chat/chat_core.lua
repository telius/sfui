local addonName, addon = ...
sfui = sfui or {}
sfui.chat = sfui.chat or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/chat/chat_core.lua
--  Shared state, defaults, opt-in theme color resolver, raw anchor helpers,
--  and module lifecycle registration for the flat lean chat module.
-- ══════════════════════════════════════════════════════════════════════════════

local chat = sfui.chat
local _G = _G
local UIParent = _G.UIParent
local C_Timer = _G.C_Timer
local hooksecurefunc = _G.hooksecurefunc
local type = _G.type
local math_max = math.max
local math_min = math.min

local issecretvalue = (sfui.safety and sfui.safety.issecretvalue) or _G.issecretvalue or function() return false end
local unpack_color = (sfui.colors and sfui.colors.unpack_color)
    or function(c, dr, dg, db, da)
        if not c then return dr or 1, dg or 1, db or 1, da or 1 end
        return c[1] or c.r or dr or 1, c[2] or c.g or dg or 1, c[3] or c.b or db or 1, c[4] or c.a or da or 1
    end
local rgb_to_hex = (sfui.colors and sfui.colors.rgb_to_hex)
    or function(r, g, b)
        return string.format("%02x%02x%02x", math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5))
    end

chat.issecretvalue = issecretvalue

local DEFAULTS = {
    bg_alpha         = 0.0,
    border_alpha     = 0.0,
    use_theme        = true,       -- native sfui.theme chrome (disable for neutral flat dark chrome)
    font_override    = false,      -- non-intrusive default: preserve Blizzard font until enabled
    font_size        = 13,
    font_outline     = "OUTLINE",  -- "", "OUTLINE", "THICKOUTLINE", "MONOCHROMEOUTLINE"
    editbox_pos      = "bottom",   -- "bottom" | "top"
    ghost_tabs       = true,       -- clean flat ghost tabs over GeneralDockManager
    custom_scrollbar = true,       -- slim 3px flat thumb (hidden while at bottom)
    url_links        = true,       -- clickable URL copy links
    hover_tooltips   = true,       -- item/spell/quest hyperlink hover tooltips
    copy_button      = "hover",    -- "hover" | "always" | "hidden"
    copy_keep_colors = false,      -- plain text by default in copy popup
    idle_fade        = false,      -- opt-in idle chrome fade
    idle_fade_delay  = 15,         -- seconds of inactivity before fading chrome
    idle_fade_alpha  = 0.0,        -- faded chrome alpha (0.0 - 0.5)
    width            = 0,          -- 0 = Blizzard native width
    height           = 0,          -- 0 = Blizzard native height
    position         = nil,        -- nil = Blizzard native position until moved via sfui.movers
}
chat.DEFAULTS = DEFAULTS

local CHAT_SCHEMA_VERSION = 3
local function migrate_chat_db(db, oldVersion)
    if type(db) ~= "table" then return end
    oldVersion = oldVersion or 0
    if oldVersion >= CHAT_SCHEMA_VERSION then return end
    if oldVersion < 2 then
        if db.use_theme == false then db.use_theme = true end
        if db.bg_alpha == 0.65 then db.bg_alpha = 0.0 end
        if db.border_alpha == 0.90 then db.border_alpha = 0.0 end
    end
    if oldVersion < 3 then
        if db.copy_button == "always" then db.copy_button = "hover" end
    end
end

chat.PAD = { l = 8, r = 8, t = 6, b = 8 }

chat.POINT_FRAC = {
    BOTTOMLEFT  = { 0,   0 },
    BOTTOM      = { 0.5, 0 },
    BOTTOMRIGHT = { 1,   0 },
    LEFT        = { 0,   0.5 },
    CENTER      = { 0.5, 0.5 },
    RIGHT       = { 1,   0.5 },
    TOPLEFT     = { 0,   1 },
    TOP         = { 0.5, 1 },
    TOPRIGHT    = { 1,   1 },
}

-- Raw C region methods bypass EditMode ChatFrame1 anchor Lua overrides cleanly.
local uiMT = UIParent and getmetatable(UIParent)
local frameMT = uiMT and uiMT.__index
chat.rawClearAllPoints = (frameMT and frameMT.ClearAllPoints) or function(f) f:ClearAllPoints() end
chat.rawSetPoint = (frameMT and frameMT.SetPoint) or function(f, ...) f:SetPoint(...) end

-- Weak-keyed side store: NEVER attach properties directly onto Blizzard ChatFrame/Tab/EditBox tables.
chat._cfd = chat._cfd or setmetatable({}, { __mode = "k" })
function chat.CFD(frame)
    if not frame then return nil end
    local d = chat._cfd[frame]
    if not d then
        d = {}
        chat._cfd[frame] = d
    end
    return d
end

if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("chat", DEFAULTS, CHAT_SCHEMA_VERSION, migrate_chat_db)
end

function chat.Get(key, fallback)
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("chat", key, fallback)
        if v ~= nil then return v end
    end
    if fallback ~= nil then return fallback end
    return DEFAULTS[key]
end

function chat.Set(key, value)
    if sfui.db and sfui.db.Set then
        sfui.db.Set("chat", key, value)
    end
end

function chat.GetActiveChatFrame()
    if _G.GENERAL_CHAT_DOCK and _G.FCFDock_GetSelectedWindow then
        local sel = _G.FCFDock_GetSelectedWindow(_G.GENERAL_CHAT_DOCK)
        if sel then return sel end
    end
    return _G.SELECTED_CHAT_FRAME or _G.ChatFrame1
end

function chat.ForEachChatFrame(fn)
    if type(fn) ~= "function" then return end
    local maxStatic = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, maxStatic do
        local cf = _G["ChatFrame" .. i]
        if cf then
            fn(cf, i)
        end
    end
    local frames = _G.CHAT_FRAMES
    if type(frames) == "table" then
        for i = maxStatic + 1, #frames do
            local name = frames[i]
            local cf = type(name) == "string" and _G[name] or name
            if cf and cf.isTemporary and cf.inUse then
                local id = (cf.GetID and cf:GetID()) or i
                fn(cf, id)
            end
        end
    end
end

local resolvedColors = {
    bg            = { 0.04, 0.04, 0.05, 0.00 },
    border        = { 0.00, 0.00, 0.00, 0.00 },
    innerBorder   = { 1.00, 1.00, 1.00, 0.08 },
    accent        = { 0.00, 0.85, 0.95, 0.95 },
    tabBg         = { 0.04, 0.04, 0.05, 0.55 },
    tabActiveBg   = { 0.07, 0.07, 0.09, 0.82 },
    tabText       = { 0.62, 0.62, 0.66, 0.92 },
    tabActiveText = { 0.96, 0.96, 0.98, 1.00 },
    scrollThumb   = { 0.75, 0.78, 0.82, 0.45 },
    ebBg          = { 0.04, 0.04, 0.05, 0.90 },
    accentHex     = "00d9f2",
}

local function set_rgba(t, r, g, b, a)
    t[1], t[2], t[3], t[4] = r, g, b, a
end

function chat.GetColors()
    local bgA = math_max(0, math_min(1, chat.Get("bg_alpha", 0.0)))
    local bdA = math_max(0, math_min(1, chat.Get("border_alpha", 0.0)))
    local useTheme = chat.Get("use_theme", true) == true
    local tabIdleA = math_max(0.55, bgA * 0.75)
    local tabActA = math_max(0.78, math_min(0.95, bgA + 0.18))
    local ebA = math_max(0.88, bgA)

    if useTheme and sfui.theme and sfui.theme.GetPalette then
        local pal = sfui.theme.GetPalette()
        if pal then
            local br, bg2, bb = unpack_color(pal.backdropColor, 0.04, 0.04, 0.05, 1)
            local ar, ag, ab = unpack_color(pal.accentColor, 0.00, 0.85, 0.95, 1)
            local hr, hg, hb = unpack_color(pal.highlightColor, ar, ag, ab, 1)
            local bdr, bdg, bdb, bda = unpack_color(pal.borderColor, 0, 0, 0, 1)
            if bda <= 0.01 then
                -- Borderless themes (e.g. Camelot) use muted highlight fallback for thin borders.
                bdr, bdg, bdb = hr * 0.45, hg * 0.45, hb * 0.45
            end
            local cr, cg, cb = unpack_color(pal.containerColor, br, bg2, bb, 1)
            local tsr, tsg, tsb = unpack_color(pal.tabSelected, ar, ag, ab, 1)
            local tnr, tng, tnb = unpack_color(pal.tabNormal, 0.85, 0.85, 0.88, 1)
            local dtr, dtg, dtb = unpack_color(pal.dimTextColor, 0.62, 0.62, 0.66, 1)

            set_rgba(resolvedColors.bg, br, bg2, bb, bgA)
            set_rgba(resolvedColors.border, bdr, bdg, bdb, bdA)
            set_rgba(resolvedColors.innerBorder, hr, hg, hb, 0.16)
            set_rgba(resolvedColors.accent, ar, ag, ab, 0.95)
            set_rgba(resolvedColors.tabBg, cr, cg, cb, tabIdleA)
            set_rgba(resolvedColors.tabActiveBg, br, bg2, bb, tabActA)
            set_rgba(resolvedColors.tabText, dtr, dtg, dtb, 0.92)
            set_rgba(resolvedColors.tabActiveText, tnr, tng, tnb, 1.00)
            set_rgba(resolvedColors.scrollThumb, tsr, tsg, tsb, 0.55)
            set_rgba(resolvedColors.ebBg, br, bg2, bb, ebA)
            resolvedColors.accentHex = rgb_to_hex(ar, ag, ab)
            return resolvedColors
        end
    end

    set_rgba(resolvedColors.bg, 0.04, 0.04, 0.05, bgA)
    set_rgba(resolvedColors.border, 0.00, 0.00, 0.00, bdA)
    set_rgba(resolvedColors.innerBorder, 1.00, 1.00, 1.00, 0.08)
    set_rgba(resolvedColors.accent, 0.00, 0.85, 0.95, 0.95)
    set_rgba(resolvedColors.tabBg, 0.04, 0.04, 0.05, tabIdleA)
    set_rgba(resolvedColors.tabActiveBg, 0.07, 0.07, 0.09, tabActA)
    set_rgba(resolvedColors.tabText, 0.62, 0.62, 0.66, 0.92)
    set_rgba(resolvedColors.tabActiveText, 0.96, 0.96, 0.98, 1.00)
    set_rgba(resolvedColors.scrollThumb, 0.75, 0.78, 0.82, 0.45)
    set_rgba(resolvedColors.ebBg, 0.04, 0.04, 0.05, ebA)
    resolvedColors.accentHex = "00d9f2"
    return resolvedColors
end

function chat.ApplyTheme()
    if not sfui.IsModuleEnabled("chat") then return end
    if chat.ApplyFrameTheme then chat.ApplyFrameTheme() end
    if chat.ApplyTabTheme then chat.ApplyTabTheme() end
    if chat.ApplyCopyTheme then chat.ApplyCopyTheme() end
end

local refreshQueued = false
local function runDeferredRefresh()
    refreshQueued = false
    if not sfui.IsModuleEnabled("chat") then return end
    if chat.ApplyChatPosition then chat.ApplyChatPosition() end
    if chat.RefreshFrame then chat.RefreshFrame() end
    if chat.RefreshTabs then chat.RefreshTabs() end
end

function chat.ScheduleRefresh()
    if refreshQueued then return end
    refreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, runDeferredRefresh)
    else
        runDeferredRefresh()
    end
end

local lastDockCount = 0
local lastSelectedCF = nil
local lastEditModeShown = false

local function onGlobalMouseUp()
    if not sfui.IsModuleEnabled("chat") then return end
    local dock = _G.GENERAL_CHAT_DOCK
    local dockList = dock and dock.DOCKED_CHAT_FRAMES
    local count = type(dockList) == "table" and #dockList or 0
    local sel = chat.GetActiveChatFrame()
    local emShown = (_G.EditModeManagerFrame and _G.EditModeManagerFrame.IsShown and _G.EditModeManagerFrame:IsShown()) and true or false
    if count ~= lastDockCount or sel ~= lastSelectedCF or emShown ~= lastEditModeShown then
        lastDockCount = count
        lastSelectedCF = sel
        lastEditModeShown = emShown
        chat.ScheduleRefresh()
    end
end

local fcfHooksInstalled = false
local FCF_SCHEDULE_HOOKS = {
    "FCF_DockUpdate",
    "FCF_Tab_OnClick",
    "FCF_OpenTemporaryWindow",
    "FCF_Close",
    "FCF_DockFrame",
    "FCF_UnDockFrame",
}

local function install_fcf_hooks()
    if fcfHooksInstalled or not hooksecurefunc then return end
    fcfHooksInstalled = true

    if _G.FCFDock_SelectWindow then
        hooksecurefunc("FCFDock_SelectWindow", function()
            if not sfui.IsModuleEnabled("chat") then return end
            if chat.RefreshTabs then chat.RefreshTabs() end
            if chat.RefreshScrollbars then chat.RefreshScrollbars() end
            if chat.RefreshCornerControls then chat.RefreshCornerControls() end
            chat.ScheduleRefresh()
        end)
    end

    local function on_fcf_change()
        if not sfui.IsModuleEnabled("chat") then return end
        chat.ScheduleRefresh()
    end
    for i = 1, #FCF_SCHEDULE_HOOKS do
        local fnName = FCF_SCHEDULE_HOOKS[i]
        if _G[fnName] then
            hooksecurefunc(fnName, on_fcf_change)
        end
    end
end

function chat:OnInit()
    if sfui.db and sfui.db.RegisterDefaults then
        sfui.db.RegisterDefaults("chat", DEFAULTS, CHAT_SCHEMA_VERSION, migrate_chat_db)
    end
end

function chat:OnEnable()
    if self._chatActive then return end
    self._chatActive = true

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if chat.WakeIdleFade then chat.WakeIdleFade() end
        chat.ScheduleRefresh()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, chat.ScheduleRefresh)
        end
    end)
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", chat.ScheduleRefresh)
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", chat.ScheduleRefresh)
    self:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", chat.ScheduleRefresh)
    self:RegisterEvent("UI_SCALE_CHANGED", chat.ScheduleRefresh)
    self:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", chat.ScheduleRefresh)
    self:RegisterEvent("CHAT_MSG_WHISPER", function()
        if chat.WakeIdleFade then chat.WakeIdleFade() end
        chat.ScheduleRefresh()
    end)
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", function()
        if chat.WakeIdleFade then chat.WakeIdleFade() end
        chat.ScheduleRefresh()
    end)
    self:RegisterEvent("GLOBAL_MOUSE_UP", onGlobalMouseUp)

    install_fcf_hooks()

    if chat.EnableFrame then chat.EnableFrame() end
    if chat.EnableTabs then chat.EnableTabs() end
    if chat.EnableCopy then chat.EnableCopy() end
    if chat.RegisterMover then chat.RegisterMover() end

    chat.ScheduleRefresh()
end

function chat:OnDisable()
    self._chatActive = false
    refreshQueued = false

    if chat.DisableCopy then chat.DisableCopy() end
    if chat.DisableTabs then chat.DisableTabs() end
    if chat.DisableFrame then chat.DisableFrame() end
end

function chat:OnSettingsChanged(key, val)
    if not sfui.IsModuleEnabled("chat") then return end

    if key == "bg_alpha" or key == "border_alpha" or key == "use_theme" then
        chat.ApplyTheme()
    elseif key == "font_override" or key == "font_size" or key == "font_outline" then
        if chat.ApplyFonts then chat.ApplyFonts() end
    elseif key == "editbox_pos" then
        if chat.ApplyEditBoxPositions then chat.ApplyEditBoxPositions() end
    elseif key == "ghost_tabs" then
        if chat.RefreshTabs then chat.RefreshTabs() end
        if chat.ApplyEditBoxPositions then chat.ApplyEditBoxPositions() end
    elseif key == "custom_scrollbar" then
        if chat.RefreshScrollbars then chat.RefreshScrollbars() end
    elseif key == "copy_button" then
        if chat.RefreshCornerControls then chat.RefreshCornerControls() end
    elseif key == "width" or key == "height" then
        if chat.ApplyChatPosition then chat.ApplyChatPosition() end
        if chat.SyncMoverSize then chat.SyncMoverSize() end
    elseif key == "position" then
        if chat.ApplyChatPosition then chat.ApplyChatPosition() end
    elseif key == "idle_fade" or key == "idle_fade_delay" or key == "idle_fade_alpha" then
        if chat.RefreshIdleFade then chat.RefreshIdleFade() end
    elseif key == "url_links" or key == "hover_tooltips" then
        if chat.RefreshCopyHooks then chat.RefreshCopyHooks() end
    else
        chat.ScheduleRefresh()
    end
end

function chat:GetDebugInfo()
    local activeFrames = 0
    chat.ForEachChatFrame(function(cf)
        local d = chat._cfd[cf]
        if d and d.bg then activeFrames = activeFrames + 1 end
    end)
    return {
        enabled     = sfui.IsModuleEnabled("chat") and true or false,
        skinned     = activeFrames,
        useTheme    = chat.Get("use_theme", true) and true or false,
        ghostTabs   = chat.Get("ghost_tabs", true) and true or false,
        idleFade    = chat.Get("idle_fade", false) and true or false,
        customPos   = chat.Get("position", nil) ~= nil,
        customSize  = (chat.Get("width", 0) > 0 or chat.Get("height", 0) > 0),
    }
end

sfui.RegisterModule("chat", chat)
