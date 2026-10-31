local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.options = sfui.options or {}

local g      = sfui.config
local common = sfui.common

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/options/tabs/tab_sync.lua
--  Multi-Account Content Synchronization Setup & Account Linking Panel
-- ══════════════════════════════════════════════════════════════════════════════

local CreateFrame   = _G.CreateFrame
local pairs         = _G.pairs
local ipairs        = _G.ipairs
local tostring      = _G.tostring
local tonumber      = _G.tonumber
local table_insert  = table.insert
local table_sort    = table.sort
local math_floor    = math.floor
local math_max      = math.max
local string_format = string.format
local string_lower  = string.lower
local GetServerTime = _G.GetServerTime
local time          = _G.time

local function create_styled_editbox(parent, width, height, placeholder, onCommit)
    local app = sfui.config.appearance
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(width or 140, height or 20)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    eb:SetBackdropColor(app.editBoxColor[1], app.editBoxColor[2], app.editBoxColor[3], app.editBoxColor[4])
    eb:SetBackdropBorderColor(0, 0, 0, 1)

    if placeholder then
        local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ph:SetPoint("LEFT", eb, "LEFT", 6, 0)
        ph:SetText(placeholder)
        ph:SetTextColor(0.45, 0.45, 0.5, 0.9)
        eb.placeholder = ph
        eb:HookScript("OnTextChanged", function(self)
            local txt = self:GetText()
            if txt and txt ~= "" then
                ph:Hide()
            else
                ph:Show()
            end
        end)
    end

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onCommit then
            onCommit(self:GetText() or "", self)
        end
    end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        if onCommit then
            onCommit(self:GetText() or "", self)
        end
    end)

    return eb
end

local function format_ago(ts)
    if not ts or ts <= 0 then return "never" end
    local now = (GetServerTime and GetServerTime()) or time()
    local diff = now - ts
    if diff < 5 then return "just now" end
    if diff < 60 then return string_format("%ds ago", diff) end
    if diff < 3600 then return string_format("%dm ago", math_floor(diff / 60)) end
    if diff < 86400 then return string_format("%dh ago", math_floor(diff / 3600)) end
    return string_format("%dd ago", math_floor(diff / 86400))
end

local function create_section_divider(parent, anchorFrame, offsetY)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, offsetY or -12)
    sep:SetPoint("RIGHT", parent, "RIGHT", -15, 0)
    sep:SetColorTexture(0.2, 0.2, 0.28, 0.9)
    return sep
end

sfui.options.RegisterTab({
    id   = "sync",
    name = "sync",
    icon = "Interface\\Icons\\Spell_Shadow_MindTwisting",
    build = function(panel)
        local sync = sfui.sync
        local s = sync and sync.GetSettings and sync.GetSettings() or {}
        local create_checkbox    = common.create_checkbox
        local create_flat_button = common.create_flat_button
        local white              = g.colors.white
        local accent             = g.appearance.highlightColor

        local COL_OFFSET_X = 265

        local function set_sync_setting(key, val)
            if sfui.db and sfui.db.Set then
                sfui.db.Set("sync", key, val)
            else
                sync.GetSettings()[key] = val
            end
        end

        -- ── 1. Header, Identity & Quick Actions ───────────────────────────────
        local header = panel:CreateFontString(nil, "OVERLAY", g.font_large or g.font)
        header:SetPoint("TOPLEFT", 15, -14)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("multi-account content sync")

        local subtext = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtext:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        subtext:SetTextColor(0.65, 0.65, 0.72)
        subtext:SetText("syncs content databases & multibox helpers across linked accounts. ui layout is never touched.")

        local enable_cb = create_checkbox(panel, "enable multi-account sync",
            function() return sync.GetSettings().enabled end,
            function(checked) set_sync_setting("enabled", checked) end,
            "enables in-game synchronization of content databases and party helpers across linked accounts.")
        enable_cb:SetPoint("TOPLEFT", subtext, "BOTTOMLEFT", 0, -10)

        local label_title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label_title:SetPoint("LEFT", enable_cb, "LEFT", 210, 0)
        label_title:SetTextColor(0.85, 0.85, 0.9)
        label_title:SetText("account label:")

        local label_eb = create_styled_editbox(panel, 82, 20, "e.g. box2", function(val)
            local trimmed = val:gsub("^%s+", ""):gsub("%s+$", "")
            set_sync_setting("accountLabel", trimmed)
            if sfui.alts and sfui.alts.PerformSync then
                sfui.alts.PerformSync(false)
            end
        end)
        label_eb:SetPoint("LEFT", label_title, "RIGHT", 6, 0)
        label_eb:SetText(s.accountLabel or "")

        local pass_title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pass_title:SetPoint("LEFT", label_eb, "RIGHT", 12, 0)
        pass_title:SetTextColor(0.85, 0.85, 0.9)
        pass_title:SetText("passcode:")

        local pass_eb = create_styled_editbox(panel, 76, 20, "optional pin", function(val)
            local trimmed = val:gsub("^%s+", ""):gsub("%s+$", "")
            set_sync_setting("passcode", trimmed)
        end)
        pass_eb:SetPoint("LEFT", pass_title, "RIGHT", 6, 0)
        pass_eb:SetText(s.passcode or "")

        -- Single-row Quick Action Bar (5 buttons across 520px)
        local sync_now_btn = create_flat_button(panel, "sync all now", 98, 20, function()
            if sync and sync.SyncAllNow then sync.SyncAllNow() end
            if panel.RefreshSyncUI then panel.RefreshSyncUI() end
        end)
        sync_now_btn:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -10)
        sync_now_btn.tooltip = "broadcasts your content manifest and synchronizes all enabled modules with linked accounts."

        local pair_target_btn = create_flat_button(panel, "pair target", 98, 20, function()
            if sync and sync.PairWithTarget then sync.PairWithTarget() end
            if panel.RefreshSyncUI then panel.RefreshSyncUI() end
        end)
        pair_target_btn:SetPoint("LEFT", sync_now_btn, "RIGHT", 7, 0)
        pair_target_btn.tooltip = "sends a pairing request to your currently targeted character and exchanges full alt rosters once confirmed."

        local pair_party_btn = create_flat_button(panel, "pair party", 98, 20, function()
            if sync and sync.PairWithParty then sync.PairWithParty() end
            if panel.RefreshSyncUI then panel.RefreshSyncUI() end
        end)
        pair_party_btn:SetPoint("LEFT", pair_target_btn, "RIGHT", 7, 0)
        pair_party_btn.tooltip = "sends a pairing request to party/raid members running sfui and exchanges full alt rosters once confirmed."

        local form_party_btn = create_flat_button(panel, "form party", 98, 20, function()
            if sync and sync.FormSyncedParty then sync.FormSyncedParty() end
        end)
        form_party_btn:SetPoint("LEFT", pair_party_btn, "RIGHT", 7, 0)
        form_party_btn.tooltip = "invites all online linked accounts into your party (synced peers auto-accept)."

        local reload_all_btn = create_flat_button(panel, "reload all", 98, 20, function()
            if sync and sync.ReloadAllClients then sync.ReloadAllClients() end
        end)
        reload_all_btn:SetPoint("LEFT", form_party_btn, "RIGHT", 7, 0)
        reload_all_btn.tooltip = "reloads the ui across all online synced clients (also available via shift+right-click on the minimap icon)."

        -- Full-width Live Status Summary Card
        local status_box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        status_box:SetPoint("TOPLEFT", sync_now_btn, "BOTTOMLEFT", 0, -8)
        status_box:SetPoint("RIGHT", panel, "RIGHT", -15, 0)
        status_box:SetHeight(44)
        common.apply_flat_backdrop(status_box, { 0.05, 0.05, 0.08, 0.85 }, { 0.2, 0.2, 0.28, 1 })

        local status_line1 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line1:SetPoint("TOPLEFT", status_box, "TOPLEFT", 10, -7)
        status_line1:SetPoint("RIGHT", status_box, "RIGHT", -10, 0)
        status_line1:SetJustifyH("LEFT")

        local status_line2 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line2:SetPoint("TOPLEFT", status_line1, "BOTTOMLEFT", 0, -5)
        status_line2:SetPoint("RIGHT", status_box, "RIGHT", -10, 0)
        status_line2:SetJustifyH("LEFT")

        -- ── 2. Multibox & Party Helpers ───────────────────────────────────────
        local sep1 = create_section_divider(panel, status_box, -10)

        local mb_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        mb_header:SetPoint("TOPLEFT", sep1, "BOTTOMLEFT", 0, -10)
        mb_header:SetTextColor(accent[1], accent[2], accent[3])
        mb_header:SetText("multibox & party helpers (hold shift to bypass)")

        local cb_mb_follow = create_checkbox(panel, "follow range & broken-follow alerts",
            function() return sync.GetSettings().mbAutoFollow ~= false end,
            function(v) set_sync_setting("mbAutoFollow", v) end,
            "alerts the party lead when /follow fails to engage out of range or breaks while moving.")
        cb_mb_follow:SetPoint("TOPLEFT", mb_header, "BOTTOMLEFT", 0, -8)

        local cb_mb_invite = create_checkbox(panel, "auto-accept invite / summon / res",
            function() return sync.GetSettings().mbAutoInvite ~= false end,
            function(v) set_sync_setting("mbAutoInvite", v) end,
            "automatically accepts party invites, summons, and resurrections from synced characters.")
        cb_mb_invite:SetPoint("LEFT", cb_mb_follow, "LEFT", COL_OFFSET_X, 0)

        local cb_mb_quest = create_checkbox(panel, "auto-quest, abandon & dialog sync",
            function() return sync.GetSettings().mbAutoQuest ~= false end,
            function(v) set_sync_setting("mbAutoQuest", v) end,
            "auto-accepts and turns in quests, syncs quest abandon, picks smart quest rewards, and mirrors lead gossip/dialog choices.")
        cb_mb_quest:SetPoint("TOPLEFT", cb_mb_follow, "BOTTOMLEFT", 0, -6)

        local cb_mb_taxi = create_checkbox(panel, "sync flight master destinations",
            function() return sync.GetSettings().mbAutoTaxi ~= false end,
            function(v) set_sync_setting("mbAutoTaxi", v) end,
            "automatically takes the same flight master destination that a synced party member selected within the last 45 seconds.")
        cb_mb_taxi:SetPoint("LEFT", cb_mb_quest, "LEFT", COL_OFFSET_X, 0)

        local cb_mb_trade = create_checkbox(panel, "auto-fill trade with routed mats",
            function() return sync.GetSettings().mbAutoTrade ~= false end,
            function(v) set_sync_setting("mbAutoTrade", v) end,
            "extends alt mail routing & synced professions into trading with synced party members, plus 'give mats' and 'dump junk' buttons on the trade frame.")
        cb_mb_trade:SetPoint("TOPLEFT", cb_mb_quest, "BOTTOMLEFT", 0, -6)

        local cb_mb_loot = create_checkbox(panel, "follower auto-pass loot rolls",
            function() return sync.GetSettings().mbFollowerPassLoot == true end,
            function(v) set_sync_setting("mbFollowerPassLoot", v) end,
            "when not the party leader in a synced group, automatically passes on loot rolls unless the item is on this character's dungeon journal wishlist.")
        cb_mb_loot:SetPoint("LEFT", cb_mb_trade, "LEFT", COL_OFFSET_X, 0)

        local cb_mb_corpse = create_checkbox(panel, "corpse quest-item loot alerts",
            function() return sync.GetSettings().mbCorpseAlert ~= false end,
            function(v) set_sync_setting("mbCorpseAlert", v) end,
            "alerts the lead window after looting a per-player quest item from a corpse if another synced party member still needs to loot their own copy.")
        cb_mb_corpse:SetPoint("TOPLEFT", cb_mb_trade, "BOTTOMLEFT", 0, -6)

        local cb_mb_hud = create_checkbox(panel, "show party status & bag/gold hud",
            function() return sync.GetSettings().mbShowHud ~= false end,
            function(v)
                set_sync_setting("mbShowHud", v)
                if sync.multibox and sync.multibox.UpdatePartySyncState then
                    sync.multibox.UpdatePartySyncState()
                end
            end,
            "shows a compact draggable party status bar with live free bag slots, team gold, click-to-target, and alt+click away/paused mode when grouped with synced characters.")
        cb_mb_hud:SetPoint("LEFT", cb_mb_corpse, "LEFT", COL_OFFSET_X, 0)

        -- ── 3. Content Modules & Transport Channels (2-Column Grid) ───────────
        local sep2 = create_section_divider(panel, cb_mb_corpse, -10)

        local mod_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        mod_header:SetPoint("TOPLEFT", sep2, "BOTTOMLEFT", 0, -10)
        mod_header:SetTextColor(accent[1], accent[2], accent[3])
        mod_header:SetText("content modules")

        local chan_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        chan_header:SetPoint("LEFT", mod_header, "LEFT", COL_OFFSET_X, 0)
        chan_header:SetTextColor(accent[1], accent[2], accent[3])
        chan_header:SetText("transport channels")

        -- Left column: Content Modules
        local cb_alts = create_checkbox(panel, "sync alts & inventory",
            function() return sync.GetSettings().syncAlts end,
            function(v) set_sync_setting("syncAlts", v) end,
            "synchronizes character levels, gold, professions, bags/bank, lockouts, currencies, and reputation.")
        cb_alts:SetPoint("TOPLEFT", mod_header, "BOTTOMLEFT", 0, -8)

        local cb_quests = create_checkbox(panel, "sync quests, journal & wishlists",
            function() return sync.GetSettings().syncQuests ~= false end,
            function(v) set_sync_setting("syncQuests", v) end,
            "synchronizes active quests, party missing-quest markers, dungeon journal quest chains, and per-character loot wishlists.")
        cb_quests:SetPoint("TOPLEFT", cb_alts, "BOTTOMLEFT", 0, -6)

        local cb_waypoints = create_checkbox(panel, "sync map waypoints to peers",
            function() return sync.GetSettings().syncWaypoints ~= false end,
            function(v) set_sync_setting("syncWaypoints", v) end,
            "automatically shares quest and dungeon journal map pins with online linked party peers.")
        cb_waypoints:SetPoint("TOPLEFT", cb_quests, "BOTTOMLEFT", 0, -6)

        local cb_recipes = create_checkbox(panel, "sync recipes & known status",
            function() return sync.GetSettings().syncRecipes end,
            function(v) set_sync_setting("syncRecipes", v) end,
            "synchronizes known crafting recipes across all characters so tooltips and recipe browser show cross-account alts.")
        cb_recipes:SetPoint("TOPLEFT", cb_waypoints, "BOTTOMLEFT", 0, -6)

        local cb_contacts = create_checkbox(panel, "sync profession contacts & finds",
            function() return sync.GetSettings().syncContacts end,
            function(v) set_sync_setting("syncContacts", v) end,
            "synchronizes discovered recipe vendors, trainers, mob recipe drops, and quest recipe rewards.")
        cb_contacts:SetPoint("TOPLEFT", cb_recipes, "BOTTOMLEFT", 0, -6)

        local cb_fishing = create_checkbox(panel, "sync fishing atlas & logbook",
            function() return sync.GetSettings().syncFishing end,
            function(v) set_sync_setting("syncFishing", v) end,
            "synchronizes per-character fishing catches, species records, and zone statistics without double-counting.")
        cb_fishing:SetPoint("TOPLEFT", cb_contacts, "BOTTOMLEFT", 0, -6)

        -- Right column: Transport Channels + Auto-Mail
        local cb_login = create_checkbox(panel, "auto-sync on login / reload",
            function() return sync.GetSettings().autoSyncOnLogin end,
            function(v) set_sync_setting("autoSyncOnLogin", v) end,
            "automatically exchanges content manifests with online linked accounts shortly after logging in.")
        cb_login:SetPoint("LEFT", cb_alts, "LEFT", COL_OFFSET_X, 0)

        local cb_party = create_checkbox(panel, "sync via party / raid",
            function() return sync.GetSettings().useParty end,
            function(v) set_sync_setting("useParty", v) end,
            "uses party/raid addon channel when grouped with your other accounts.")
        cb_party:SetPoint("LEFT", cb_quests, "LEFT", COL_OFFSET_X, 0)

        local cb_whisper = create_checkbox(panel, "sync via whisper (linked chars)",
            function() return sync.GetSettings().useWhisper end,
            function(v) set_sync_setting("useWhisper", v) end,
            "uses direct addon whispers to linked characters on the same realm/faction even when ungrouped.")
        cb_whisper:SetPoint("LEFT", cb_waypoints, "LEFT", COL_OFFSET_X, 0)

        local cb_bnet = create_checkbox(panel, "sync via battle.net friends",
            function() return sync.GetSettings().useBNet end,
            function(v) set_sync_setting("useBNet", v) end,
            "uses battle.net gamedata channel when your accounts are battle.net friends.")
        cb_bnet:SetPoint("LEFT", cb_recipes, "LEFT", COL_OFFSET_X, 0)

        local cb_guild = create_checkbox(panel, "sync via guild",
            function() return sync.GetSettings().useGuild end,
            function(v) set_sync_setting("useGuild", v) end,
            "uses guild addon channel when characters share a guild.")
        cb_guild:SetPoint("LEFT", cb_contacts, "LEFT", COL_OFFSET_X, 0)

        local cb_mail = create_checkbox(panel, "sync auto-mail routing rules",
            function() return sync.GetSettings().syncMail end,
            function(v) set_sync_setting("syncMail", v) end,
            "synchronizes auto-mail item routes and disenchanter assignments across linked accounts.")
        cb_mail:SetPoint("LEFT", cb_fishing, "LEFT", COL_OFFSET_X, 0)

        -- ── 4. Linked Characters & Accounts (Full-Width List) ─────────────────
        local sep3 = create_section_divider(panel, cb_fishing, -10)

        local peers_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        peers_header:SetPoint("TOPLEFT", sep3, "BOTTOMLEFT", 0, -10)
        peers_header:SetTextColor(accent[1], accent[2], accent[3])
        peers_header:SetText("linked characters & accounts")

        local add_eb = create_styled_editbox(panel, 220, 20, "character name (or name-realm)", nil)
        add_eb:SetPoint("LEFT", peers_header, "LEFT", COL_OFFSET_X - 45, 0)

        local function do_add_peer()
            local txt = add_eb:GetText() or ""
            local trimmed = txt:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed == "" then return end
            add_eb:SetText("")
            add_eb:ClearFocus()
            if sync and sync.PairWithCharacter then
                sync.PairWithCharacter(trimmed)
            end
            if panel.RefreshSyncUI then
                panel.RefreshSyncUI()
            end
        end

        add_eb:SetScript("OnEnterPressed", function()
            do_add_peer()
        end)

        local add_btn = create_flat_button(panel, "add & pair", 84, 20, do_add_peer)
        add_btn:SetPoint("LEFT", add_eb, "RIGHT", 6, 0)
        add_btn.tooltip = "adds this character to your linked peers and sends a whisper pairing request to import all alts on that account."

        local list_bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        list_bg:SetPoint("TOPLEFT", peers_header, "BOTTOMLEFT", 0, -10)
        list_bg:SetPoint("RIGHT", panel, "RIGHT", -15, 0)
        list_bg:SetHeight(132)
        common.apply_flat_backdrop(list_bg, { 0.04, 0.04, 0.06, 0.9 }, { 0.18, 0.18, 0.25, 1 })

        local sf, sc = common.create_scroll_frame(list_bg, nil, 500, 126)
        sf:SetPoint("TOPLEFT", list_bg, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", list_bg, "BOTTOMRIGHT", -14, 4)

        local empty_label = list_bg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty_label:SetPoint("CENTER", list_bg, "CENTER", 0, 0)
        empty_label:SetText("no linked characters yet — target your other character and click 'pair target', or type a character name above.")
        empty_label:SetJustifyH("CENTER")

        local peerRows = {}

        local function get_peer_row(idx)
            local row = peerRows[idx]
            if row then return row end

            row = CreateFrame("Frame", nil, sc, "BackdropTemplate")
            row:SetHeight(24)
            common.apply_flat_backdrop(row, { 0.08, 0.08, 0.11, 0.85 }, { 0.16, 0.16, 0.22, 1 })

            row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameFs:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.nameFs:SetJustifyH("LEFT")

            row.removeBtn = common.create_remove_button(row, nil, 18, 18, "remove linked character")
            row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

            row.syncBtn = create_flat_button(row, "sync", 44, 18)
            row.syncBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -6, 0)
            row.syncBtn.tooltip = "whisper-sync content with this character now."

            row.metaFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.metaFs:SetPoint("RIGHT", row.syncBtn, "LEFT", -10, 0)
            row.metaFs:SetJustifyH("RIGHT")

            peerRows[idx] = row
            return row
        end

        local allCheckboxes = {
            { cb = enable_cb,    get = function(c) return c.enabled == true end },
            { cb = cb_alts,      get = function(c) return c.syncAlts == true end },
            { cb = cb_recipes,   get = function(c) return c.syncRecipes == true end },
            { cb = cb_contacts,  get = function(c) return c.syncContacts == true end },
            { cb = cb_fishing,   get = function(c) return c.syncFishing == true end },
            { cb = cb_mail,      get = function(c) return c.syncMail == true end },
            { cb = cb_quests,    get = function(c) return c.syncQuests ~= false end },
            { cb = cb_waypoints, get = function(c) return c.syncWaypoints ~= false end },
            { cb = cb_login,     get = function(c) return c.autoSyncOnLogin == true end },
            { cb = cb_party,     get = function(c) return c.useParty == true end },
            { cb = cb_whisper,   get = function(c) return c.useWhisper == true end },
            { cb = cb_guild,     get = function(c) return c.useGuild == true end },
            { cb = cb_bnet,      get = function(c) return c.useBNet == true end },
            { cb = cb_mb_follow, get = function(c) return c.mbAutoFollow ~= false end },
            { cb = cb_mb_invite, get = function(c) return c.mbAutoInvite ~= false end },
            { cb = cb_mb_quest,  get = function(c) return c.mbAutoQuest ~= false end },
            { cb = cb_mb_taxi,   get = function(c) return c.mbAutoTaxi ~= false end },
            { cb = cb_mb_trade,  get = function(c) return c.mbAutoTrade ~= false end },
            { cb = cb_mb_corpse, get = function(c) return c.mbCorpseAlert ~= false end },
            { cb = cb_mb_hud,    get = function(c) return c.mbShowHud ~= false end },
            { cb = cb_mb_loot,   get = function(c) return c.mbFollowerPassLoot == true end },
        }

        function panel.RefreshSyncUI()
            local cur = sync.GetSettings()
            if not label_eb:HasFocus() then
                label_eb:SetText(cur.accountLabel or "")
            end
            if not pass_eb:HasFocus() then
                pass_eb:SetText(cur.passcode or "")
            end
            for _, entry in ipairs(allCheckboxes) do
                if entry.cb and entry.cb.SetChecked then
                    entry.cb:SetChecked(entry.get(cur))
                end
            end

            local counts = (sync.GetContentCounts and sync.GetContentCounts()) or {}
            local st = sync.stats or {}
            local qLen = (sync.codec and sync.codec.GetQueueLength and sync.codec.GetQueueLength()) or 0

            status_line1:SetText(string_format(
                "|cffaaaaaaalts:|r %d |cff888888(%d remote)|r   |cffaaaaaarecipes:|r %d   |cffaaaaaacontacts:|r %d   |cffaaaaaafish:|r %d",
                counts.alts or 0, counts.remoteAlts or 0, counts.recipes or 0, counts.contacts or 0, counts.fish or 0
            ))
            local lastPeerStr = st.lastPeer and (" |cff00ffff(" .. tostring(st.lastPeer):lower() .. ")|r") or ""
            status_line2:SetText(string_format(
                "|cffaaaaaalinked chars:|r %d   |cffaaaaaapackets:|r %d sent / %d recv   |cffaaaaaaqueue:|r %d   |   |cffaaaaaalast sync:|r %s%s",
                counts.peers or 0, st.packetsSent or 0, st.packetsReceived or 0, qLen,
                format_ago(st.lastSyncTime), lastPeerStr
            ))

            -- Populate peer rows
            local list = {}
            for key, p in pairs(cur.peers or {}) do
                if type(p) == "table" and p.name then
                    table_insert(list, {
                        key  = key,
                        peer = p,
                    })
                end
            end

            table_sort(list, function(a, b)
                local la = string_lower(a.peer.accountLabel or "zzzz")
                local lb = string_lower(b.peer.accountLabel or "zzzz")
                if la ~= lb then return la < lb end
                return string_lower(a.peer.name or "") < string_lower(b.peer.name or "")
            end)

            for _, r in ipairs(peerRows) do
                r:Hide()
            end

            if #list == 0 then
                empty_label:Show()
                sc:SetHeight(80)
                return
            end

            empty_label:Hide()
            local rowW = math_max(460, (sf:GetWidth() or 500) - 4)
            sc:SetWidth(rowW)

            local y = 0
            for i, item in ipairs(list) do
                local row = get_peer_row(i)
                local p = item.peer
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -y)
                row:SetSize(rowW, 24)

                local nameDisplay = string_lower(p.name or "unknown")
                if p.class and common.get_class_color then
                    local r, gCol, b = common.get_class_color(p.class)
                    if r and gCol and b then
                        nameDisplay = string_format("|cff%02x%02x%02x%s|r", r * 255, gCol * 255, b * 255, nameDisplay)
                    end
                end
                if p.accountLabel and p.accountLabel ~= "" then
                    nameDisplay = nameDisplay .. " |cff8888aa[" .. string_lower(p.accountLabel) .. "]|r"
                end
                if p.level and tonumber(p.level) and tonumber(p.level) > 0 then
                    nameDisplay = nameDisplay .. " |cff777777lv." .. tonumber(p.level) .. "|r"
                end
                row.nameFs:SetText(nameDisplay)
                row.metaFs:SetText("last sync: " .. format_ago(p.lastSync or p.lastSeen))

                local targetName = p.name
                local peerKey = item.key
                row.syncBtn:SetScript("OnClick", function()
                    if sync and sync.SendHelloToPeer then
                        sync.SendHelloToPeer(targetName, "WHISPER")
                        sfui.common.print("sync: syncing with |cff00ffff" .. string_lower(targetName) .. "|r...")
                    end
                end)
                row.removeBtn:SetScript("OnClick", function()
                    if sync and sync.RemovePeer then
                        sync.RemovePeer(peerKey)
                    end
                    panel.RefreshSyncUI()
                end)

                row:Show()
                y = y + 26
            end

            sc:SetHeight(math_max(80, y))
        end

        if sfui.events and sfui.events.RegisterMessage then
            sfui.events.RegisterMessage("SFUI_SYNC_PEERS_UPDATED", function()
                if panel:IsVisible() and panel.RefreshSyncUI then
                    panel.RefreshSyncUI()
                end
            end)
            sfui.events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", function()
                if panel:IsVisible() and panel.RefreshSyncUI then
                    panel.RefreshSyncUI()
                end
            end)
        end

        panel.RefreshSyncUI()
    end,
    onShow = function(panel)
        local content = panel.content_panel or panel
        if content and content.RefreshSyncUI then
            content.RefreshSyncUI()
        end
    end,
})
