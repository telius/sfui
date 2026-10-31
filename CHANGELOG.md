# changelog

## v1.127 (2026-10-31)

### features & improvements

- **multi-account sync & multibox party engine (`frames/sync/codec.lua`, `frames/sync/merge.lua`, `frames/sync/sync.lua`, `frames/sync/multibox.lua`, `frames/sync/quests.lua`, `frames/sync/trade.lua`, `frames/sync/hud.lua`, `frames/options/tabs/tab_sync.lua`, `commands.lua`)**:
  - added cross-account synchronization for alt rosters, active quests, dungeon journal wishlists, profession recipes, npc contacts, fishing ledgers, mail routing tables, and shared waypoints.
  - added lazy party-sync submodules that remain dormant with zero active event listeners or ui frames until grouped with a synced character (`multibox.IsActiveSyncParty()`).
  - added synchronized quest automation (`frames/sync/quests.lua`): quest abandon sync with completed-quest protection, multi-step turn-in catch-up (`GossipFrame` -> `QuestFrameProgressPanel` -> `QuestFrameRewardPanel`), smart quest reward scoring with manual override preservation, and gossip/dialog/popup mirroring.
  - added synchronized flight master selection (`frames/sync/multibox.lua`, `frames/sync/quests.lua`): cached taxi node names on `TAXIMAP_OPENED`, supported multi-hop (`DISTANT`) destinations via `GetNumRoutes`, immediately triggered flight selection when `DELTA_TAXI` arrives on open flight maps, and fixed 0-based `orderIndex` gossip option replay.
  - added automated trade routing (`frames/sync/trade.lua`) extending `SfuiDB.mail.routes` to direct trades with synced party members (`Alt`+right-click to bind item routes, auto-fill up to 6 trade slots, and safe dual-accept).
  - added corpse shared quest-item alerts (`frames/sync/multibox.lua`) when leaving a corpse that still holds a non-stackable quest item needed by another synced party member.
  - added a compact movable synced-party status hud (`frames/sync/hud.lua`) displaying level, xp %, rested xp %, durability %, free bag slots, and mount/follow/away state.
  - fixed remote reload (`CMD_RELOAD`) on follower clients (`frames/sync/sync.lua`) to arm the hardware-event reload catcher without calling `C_UI.Reload()` directly from `CHAT_MSG_ADDON`.

- **bonus roll loot tracker (`frames/gear/bonusroll.lua`, `frames/gear/lootviewer.lua`)**:
  - added 3-way loot resolution matching (`BonusRollFrame.CurrentItemLink`, `CHAT_MSG_LOOT`, and `BAG_UPDATE_DELAYED` inventory diffing) and an item-id fallback index so items acquired via bonus roll or normal boss drops are reliably marked as collected across difficulty variants.

- **quest tracker warbound completed color option (`frames/options/tabs/tab_objectives.lua`, `frames/quests/modules/q_quests.lua`)**:
  - added a `recolor warbound completed quests` toggle (`SfuiDB.questlogRecolorWarband`, enabled by default) in `frames/options/tabs/tab_objectives.lua` to control the dark-red title tint on account-completed quests.

- **unattached default player castbar suppression (`frames/bars/castbar.lua`)**:
  - moved the unattached default `PlayerCastingBarFrame` offscreen (`TOP`, `UIParent`, `BOTTOM`, `0, -5000`) and clamped its alpha to `0` across `OnShow`, `ApplyAlpha`, `ApplySystemAnchor`, `BottomManagedFrameContainer:Layout`, and `PlayerFrame_DetachCastBar` whenever sfui's player castbar is enabled, restoring it cleanly when disabled.

- **cooldown viewer taint fix (`frames/tracking/panels.lua`, `frames/tracking/buffs.lua`, `frames/tracking/trackedbars.lua`, `frames/tracking/cdm.lua`)**:
  - removed addon calls into `CooldownViewerSettings:GetDataProvider()` and `GetLayoutManager():SaveLayouts()` so `CooldownViewerSettingsDataProviderMixin` remains untainted and never blocks `SetHiddenGroupBuffs()` or `SetGroupBuffVisualAlerts()`.
