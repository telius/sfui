# changelog

## v1.153 (2026-11-21)

### new features & improvements

- **adventure guide sets & tier tracker (`data/sets_camelot.lua`, `frames/gear/sets.lua`, `frames/dungeonjournal/dungeonjournal.lua`, `frames/gear/upgrades.lua`, `frames/dungeonjournal/dj_tooltips.lua`, `commands.lua`, `sfui.toc`)**:
  - added a dedicated top-level `sets` tab next to `upgrades` (and `/sf sets`, `/sf set`, `/sf tier`) covering all 44 wow forever sets (9 tier 0, 18 forever tier 0.5 role variants with 4-stage alliance/horde quest links, and 17 classic + forever dungeon sets including chain of the scarlet crusade).
  - includes live equipped/bags/bank/alt ownership tracking, audited per-class armor/dual-wield/db2 class filtering, tsm boe auction pricing, clickable `run next` dungeon farm chips, batch wishlist, full-set dressing-room try-on, `[t0]`/`[t0.5]`/`[set]` badges in upgrades, and item tooltip drop/upgrade hints.
- **chat module, copy window & font size sync (`frames/chat/chat_core.lua`, `frames/chat/chat_frame.lua`, `frames/chat/chat_tabs.lua`, `frames/chat/chat_copy.lua`, `frames/options/tabs/tab_chat.lua`)**:
  - added the modular chat frame, tab bar, searchable copy window, and options tab, and synced blizzard tab font-size changes directly into `sfui` saved settings.
- **on-demand dungeon maps companion addon (`sfui_dungeon_maps/sfui_dungeon_maps.toc`, `sfui_dungeon_maps/data/dungeon_maps_camelot.lua`, `frames/dungeonjournal/dj_map.lua`, `data/dj_maps_camelot.lua`, `.pkgmeta`)**:
  - moved custom wow forever dungeon maps and classic map patches into the load-on-demand `sfui_dungeon_maps` companion addon packaged alongside `sfui`, removing obsolete static map assets.
- **quest tracker section abandon, tooltips & sync (`frames/quests/engine/q_blocks.lua`, `frames/quests/engine/q_layout.lua`, `frames/quests/helpers/q_common.lua`, `frames/quests/helpers/q_tooltip.lua`, `frames/sync/sync.lua`, `frames/sync/codec.lua`, `frames/sync/merge.lua`)**:
  - added ctrl-click on tracker section headers to abandon all abandonable quests in a section via a confirmation dialog listing quests and destroyed items, expanded quest tooltips, and improved multi-account quest sync cadence with spec-colored peer abbreviations.

### bug fixes & performance

- **cpu, memory & codebase standardization (`dispatcher.lua`, `core/safety.lua`, `core/pool.lua`, `core/widgets.lua`, `frames/experience/bar_base.lua`, `frames/alts/alts.lua`, `frames/bars/swing.lua`, `frames/tracking/panels.lua`, `common.lua`)**:
  - centralized shared bar, widget, pooling, and safety helpers, reliably suppressed and disarmed blizzard cooldown viewer frames, reduced hot-path allocations across tracking, experience, alts, and swing modules, and fixed opening the class trainer info window in combat.
- **dungeon journal quest share check & camelot data updates (`frames/dungeonjournal/dj_quests.lua`, `data/dj_camelot.lua`, `data/recipes_camelot.lua`, `data/fishing_camelot.lua`)**:
  - restored `isquestshareable` in `frames/dungeonjournal/dj_quests.lua` to fix nil-call errors on quest list and detail views, and refreshed camelot dungeon, recipe, and fishing datasets.
