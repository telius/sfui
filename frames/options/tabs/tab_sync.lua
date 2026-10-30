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

local CreateFrame  = _G.CreateFrame
local pairs        = _G.pairs
local ipairs       = _G.ipairs
local tostring     = _G.tostring
local tonumber     = _G.tonumber
local table_insert = table.insert
local table_sort   = table.sort
local math_floor   = math.floor
local math_max     = math.max
local string_format = string.format
local string_lower = string.lower
local GetServerTime = _G.GetServerTime
local time         = _G.time

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
        local ph = eb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
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

        local function set_sync_setting(key, val)
            if sfui.db and sfui.db.Set then
                sfui.db.Set("sync", key, val)
            else
                sync.GetSettings()[key] = val
            end
        end

        -- ── Left Column: Configuration & Quick Actions ────────────────────────
        local header = panel:CreateFontString(nil, "OVERLAY", g.font)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("multi-account content sync")

        local subtext = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtext:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        subtext:SetTextColor(0.65, 0.65, 0.72)
        subtext:SetText("syncs content data only (alts, recipes, contacts, fishing, mail routes). ui layout is never touched.")

        local enable_cb = create_checkbox(panel, "enable multi-account content sync",
            function() return sync.GetSettings().enabled end,
            function(checked) set_sync_setting("enabled", checked) end,
            "enables in-game synchronization of content databases across linked accounts.")
        enable_cb:SetPoint("TOPLEFT", subtext, "BOTTOMLEFT", 0, -10)

        -- Identity inputs (Account Label & Pairing Passcode)
        local label_title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label_title:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -12)
        label_title:SetTextColor(0.85, 0.85, 0.9)
        label_title:SetText("this account label:")

        local label_eb = create_styled_editbox(panel, 110, 20, "e.g. main, box2", function(val)
            local trimmed = val:gsub("^%s+", ""):gsub("%s+$", "")
            set_sync_setting("accountLabel", trimmed)
            if sfui.alts and sfui.alts.PerformSync then
                sfui.alts.PerformSync(false)
            end
        end)
        label_eb:SetPoint("LEFT", label_title, "LEFT", 115, 0)
        label_eb:SetText(s.accountLabel or "")

        local pass_title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pass_title:SetPoint("TOPLEFT", label_title, "BOTTOMLEFT", 0, -10)
        pass_title:SetTextColor(0.85, 0.85, 0.9)
        pass_title:SetText("pairing passcode:")

        local pass_eb = create_styled_editbox(panel, 110, 20, "optional pin", function(val)
            local trimmed = val:gsub("^%s+", ""):gsub("%s+$", "")
            set_sync_setting("passcode", trimmed)
        end)
        pass_eb:SetPoint("LEFT", pass_title, "LEFT", 115, 0)
        pass_eb:SetText(s.passcode or "")

        -- Action Buttons Row
        local sync_now_btn = create_flat_button(panel, "sync all now", 88, 22, function()
            if sync and sync.SyncAllNow then sync.SyncAllNow() end
            if panel.RefreshSyncUI then panel.RefreshSyncUI() end
        end)
        sync_now_btn:SetPoint("TOPLEFT", pass_title, "BOTTOMLEFT", 0, -14)
        sync_now_btn.tooltip = "broadcasts your content manifest and synchronizes all enabled modules with linked accounts."

        local pair_target_btn = create_flat_button(panel, "pair target", 82, 22, function()
            if sync and sync.PairWithTarget then sync.PairWithTarget() end
            if panel.RefreshSyncUI then panel.RefreshSyncUI() end
        end)
        pair_target_btn:SetPoint("LEFT", sync_now_btn, "RIGHT", 6, 0)
        pair_target_btn.tooltip = "links with your currently targeted character and exchanges full alt rosters between both accounts."

        local pair_party_btn = create_flat_button(panel, "pair party", 82, 22, function()
            if sync and sync.PairWithParty then sync.PairWithParty() end
            if panel.RefreshSyncUI then panel.RefreshSyncUI() end
        end)
        pair_party_btn:SetPoint("LEFT", pair_target_btn, "RIGHT", 6, 0)
        pair_party_btn.tooltip = "links with all party/raid members running sfui and exchanges full alt rosters."

        -- Content Modules Section
        local mod_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        mod_header:SetPoint("TOPLEFT", sync_now_btn, "BOTTOMLEFT", 0, -18)
        mod_header:SetTextColor(accent[1], accent[2], accent[3])
        mod_header:SetText("content modules")

        local cb_alts = create_checkbox(panel, "sync alts & inventory",
            function() return sync.GetSettings().syncAlts end,
            function(v) set_sync_setting("syncAlts", v) end,
            "synchronizes character levels, gold, professions, bags/bank, lockouts, currencies, and reputation.")
        cb_alts:SetPoint("TOPLEFT", mod_header, "BOTTOMLEFT", 0, -8)

        local cb_recipes = create_checkbox(panel, "sync recipes & known status",
            function() return sync.GetSettings().syncRecipes end,
            function(v) set_sync_setting("syncRecipes", v) end,
            "synchronizes known crafting recipes across all characters so tooltips and recipe browser show cross-account alts.")
        cb_recipes:SetPoint("TOPLEFT", cb_alts, "BOTTOMLEFT", 0, -6)

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

        local cb_mail = create_checkbox(panel, "sync auto-mail routing rules",
            function() return sync.GetSettings().syncMail end,
            function(v) set_sync_setting("syncMail", v) end,
            "synchronizes auto-mail item routes and disenchanter assignments across linked accounts.")
        cb_mail:SetPoint("TOPLEFT", cb_fishing, "BOTTOMLEFT", 0, -6)

        local cb_quests = create_checkbox(panel, "sync quests, dungeon journal & wishlists",
            function() return sync.GetSettings().syncQuests ~= false end,
            function(v) set_sync_setting("syncQuests", v) end,
            "synchronizes active quests, party missing-quest markers, dungeon journal quest chains, and per-character loot wishlists.")
        cb_quests:SetPoint("TOPLEFT", cb_mail, "BOTTOMLEFT", 0, -6)

        local cb_waypoints = create_checkbox(panel, "sync map waypoints to peers",
            function() return sync.GetSettings().syncWaypoints ~= false end,
            function(v) set_sync_setting("syncWaypoints", v) end,
            "automatically shares quest and dungeon journal map pins with online linked party peers.")
        cb_waypoints:SetPoint("TOPLEFT", cb_quests, "BOTTOMLEFT", 0, -6)

        -- Channels Section
        local chan_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        chan_header:SetPoint("TOPLEFT", cb_waypoints, "BOTTOMLEFT", 0, -14)
        chan_header:SetTextColor(accent[1], accent[2], accent[3])
        chan_header:SetText("transport channels")

        local cb_login = create_checkbox(panel, "auto-sync on login / reload",
            function() return sync.GetSettings().autoSyncOnLogin end,
            function(v) set_sync_setting("autoSyncOnLogin", v) end,
            "automatically exchanges content manifests with online linked accounts shortly after logging in.")
        cb_login:SetPoint("TOPLEFT", chan_header, "BOTTOMLEFT", 0, -8)

        local cb_party = create_checkbox(panel, "sync via party / raid",
            function() return sync.GetSettings().useParty end,
            function(v) set_sync_setting("useParty", v) end,
            "uses party/raid addon channel when grouped with your other accounts.")
        cb_party:SetPoint("TOPLEFT", cb_login, "BOTTOMLEFT", 0, -6)

        local cb_whisper = create_checkbox(panel, "sync via whisper (linked characters)",
            function() return sync.GetSettings().useWhisper end,
            function(v) set_sync_setting("useWhisper", v) end,
            "uses direct addon whispers to linked characters on the same realm/faction even when ungrouped.")
        cb_whisper:SetPoint("TOPLEFT", cb_party, "BOTTOMLEFT", 0, -6)

        local cb_guild = create_checkbox(panel, "sync via guild",
            function() return sync.GetSettings().useGuild end,
            function(v) set_sync_setting("useGuild", v) end,
            "uses guild addon channel when characters share a guild.")
        cb_guild:SetPoint("TOPLEFT", cb_whisper, "BOTTOMLEFT", 0, -6)

        local cb_bnet = create_checkbox(panel, "sync via battle.net friends",
            function() return sync.GetSettings().useBNet end,
            function(v) set_sync_setting("useBNet", v) end,
            "uses battle.net gamedata channel when your accounts are battle.net friends.")
        cb_bnet:SetPoint("TOPLEFT", cb_guild, "BOTTOMLEFT", 0, -6)

        -- ── Right Column: Live Status & Linked Characters List ────────────────
        local right_x = 305

        local status_box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        status_box:SetPoint("TOPLEFT", panel, "TOPLEFT", right_x, -42)
        status_box:SetPoint("RIGHT", panel, "RIGHT", -15, 0)
        status_box:SetHeight(92)
        common.apply_flat_backdrop(status_box, { 0.05, 0.05, 0.08, 0.85 }, { 0.2, 0.2, 0.28, 1 })

        local status_title = status_box:CreateFontString(nil, "OVERLAY", g.font)
        status_title:SetPoint("TOPLEFT", 10, -8)
        status_title:SetTextColor(accent[1], accent[2], accent[3])
        status_title:SetText("sync status & database summary")

        local status_line1 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line1:SetPoint("TOPLEFT", status_title, "BOTTOMLEFT", 0, -6)
        status_line1:SetJustifyH("LEFT")

        local status_line2 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line2:SetPoint("TOPLEFT", status_line1, "BOTTOMLEFT", 0, -5)
        status_line2:SetJustifyH("LEFT")

        local status_line3 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line3:SetPoint("TOPLEFT", status_line2, "BOTTOMLEFT", 0, -5)
        status_line3:SetJustifyH("LEFT")

        -- Add Linked Character Row
        local peers_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        peers_header:SetPoint("TOPLEFT", status_box, "BOTTOMLEFT", 0, -14)
        peers_header:SetTextColor(accent[1], accent[2], accent[3])
        peers_header:SetText("linked characters & accounts")

        local add_eb = create_styled_editbox(panel, 165, 22, "character name (or name-realm)", nil)
        add_eb:SetPoint("TOPLEFT", peers_header, "BOTTOMLEFT", 0, -8)

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

        local add_btn = create_flat_button(panel, "add & pair", 82, 22, do_add_peer)
        add_btn:SetPoint("LEFT", add_eb, "RIGHT", 6, 0)
        add_btn.tooltip = "adds this character to your linked peers and sends a whisper pairing request to import all alts on that account."

        -- Scrollable Peer List Container
        local list_bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        list_bg:SetPoint("TOPLEFT", add_eb, "BOTTOMLEFT", 0, -8)
        list_bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -15, 15)
        common.apply_flat_backdrop(list_bg, { 0.04, 0.04, 0.06, 0.9 }, { 0.18, 0.18, 0.25, 1 })

        local sf, sc = common.create_scroll_frame(list_bg, nil, 260, 200)
        sf:SetPoint("TOPLEFT", list_bg, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", list_bg, "BOTTOMRIGHT", -14, 4)

        local empty_label = list_bg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty_label:SetPoint("CENTER", list_bg, "CENTER", 0, 0)
        empty_label:SetText("no linked characters yet.\ntarget your other character and click 'pair target',\nor type a character name above.")
        empty_label:SetJustifyH("CENTER")

        local peerRows = {}

        local function get_peer_row(idx)
            local row = peerRows[idx]
            if row then return row end

            row = CreateFrame("Frame", nil, sc, "BackdropTemplate")
            row:SetHeight(24)
            common.apply_flat_backdrop(row, { 0.08, 0.08, 0.11, 0.85 }, { 0.16, 0.16, 0.22, 1 })

            row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameFs:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.nameFs:SetJustifyH("LEFT")

            row.removeBtn = common.create_remove_button(row, nil, 18, 18, "remove linked character")
            row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -3, 0)

            row.syncBtn = create_flat_button(row, "sync", 40, 18)
            row.syncBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)
            row.syncBtn.tooltip = "whisper-sync content with this character now."

            row.metaFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.metaFs:SetPoint("RIGHT", row.syncBtn, "LEFT", -6, 0)
            row.metaFs:SetJustifyH("RIGHT")

            peerRows[idx] = row
            return row
        end

        function panel.RefreshSyncUI()
            local cur = sync.GetSettings()
            if not label_eb:HasFocus() then
                label_eb:SetText(cur.accountLabel or "")
            end
            if not pass_eb:HasFocus() then
                pass_eb:SetText(cur.passcode or "")
            end

            local counts = (sync.GetContentCounts and sync.GetContentCounts()) or {}
            local st = sync.stats or {}
            local qLen = (sync.codec and sync.codec.GetQueueLength and sync.codec.GetQueueLength()) or 0

            status_line1:SetText(string_format(
                "|cffaaaaaaalts:|r %d |cff888888(%d remote)|r   |cffaaaaaarecipes:|r %d   |cffaaaaaacontacts:|r %d   |cffaaaaaafish:|r %d",
                counts.alts or 0, counts.remoteAlts or 0, counts.recipes or 0, counts.contacts or 0, counts.fish or 0
            ))
            status_line2:SetText(string_format(
                "|cffaaaaaalinked chars:|r %d   |cffaaaaaapackets:|r %d sent / %d recv   |cffaaaaaaqueue:|r %d",
                counts.peers or 0, st.packetsSent or 0, st.packetsReceived or 0, qLen
            ))
            local lastPeerStr = st.lastPeer and (" |cff00ffff(" .. tostring(st.lastPeer):lower() .. ")|r") or ""
            status_line3:SetText(string_format(
                "|cffaaaaaalast sync:|r %s%s",
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
                sc:SetHeight(100)
                return
            end

            empty_label:Hide()
            local rowW = math_max(220, (sf:GetWidth() or 260) - 4)
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
                row.nameFs:SetText(nameDisplay)
                row.metaFs:SetText(format_ago(p.lastSync or p.lastSeen))

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

            sc:SetHeight(math_max(100, y))
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
        if panel and panel.RefreshSyncUI then
            panel.RefreshSyncUI()
        end
    end,
})

