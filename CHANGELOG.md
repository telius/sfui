# changelog

## v1.149 (2026-11-16)

### new features & improvements

- **expandable fishing hud, container buttons, bite windows & skillup tracking (`frames/fishing/fishing_hud.lua`, `data/fishing_camelot.lua`, `frames/automation/fishing.lua`, `frames/options/tabs/tab_fishing.lua`, `commands.lua`)**:
  - upgraded the floating fishing hud with an expandable current-zone species drawer displaying drop rates, time-of-day and seasonal bite windows, session catches, lifetime catches, and interactive bag/goal counters with goal alerts.
  - added a secure clickable bag-container button for clams, crates, and bloated fish alongside lure status, free-bag warnings, expected catches-per-skillup progress, and `/sfui fish collapse`.
- **camelot dungeon maps & multi-floor subzone detection (`data/dj_maps_camelot.lua`, `data/dj_camelot.lua`, `frames/dungeonjournal/dj_map.lua`, `frames/dungeonjournal/dungeonjournal.lua`, `media/dungeonmaps/`)**:
  - integrated new custom dungeon map floors and artwork for alcaz prison, blackmaw hold (6 floors), the drowned city / atal'byzal, sunken temple, and serpent statue (replacing `media/dungeonmaps/TheTempleOfAtalHakkar1.blp`).
  - expanded automatic in-instance subzone-to-floor detection across alcaz prison, blackmaw hold, the drowned city, scholomance, and stratholme.
- **trainer "train all" button & spellbook catalog improvements (`frames/automation/automation.lua`, `frames/character/trainer.lua`, `frames/automation/rankup.lua`, `frames/options/tabs/tab_automation.lua`, `common.lua`, `config.lua`)**:
  - added a configurable "train all" button with affordability, free profession-slot, and cost summary tooltips on class and profession trainers (`frames/automation/automation.lua`, `frames/options/tabs/tab_automation.lua`).
  - improved camelot spellbook trainer scanning, rank cost lookups, flyout/future spell indexing, and low-rank spell reconciliation (`frames/character/trainer.lua`, `frames/automation/rankup.lua`).
- **party class buff reminders & multibox quest reward automation (`frames/reminders/buffs_party.lua`, `frames/reminders/buffs_data.lua`, `frames/reminders/buffs_providers.lua`, `frames/reminders/buffs_scan.lua`, `frames/options/tabs/tab_buffs.lua`, `frames/ring/providers/ring_specs.lua`, `frames/ring/providers/ring_utility.lua`, `frames/sync/quests.lua`, `frames/sync/sync.lua`, `frames/options/tabs/tab_sync.lua`)**:
  - expanded party buff reminders beyond paladin blessings to detect missing single-target class buffs (`power word: fortitude`, `divine spirit`, `arcane intellect`, and `mark of the wild`) with per-member radial ring slices.
  - added optional multibox auto-complete and smart quest reward selection (`frames/sync/quests.lua`, `frames/options/tabs/tab_sync.lua`) that picks the highest spec upgrade or best vendor-gold reward unless shift is held.

### bug fixes & performance

- **dungeon journal & world map lag elimination (`frames/dungeonjournal/dj_sidebar.lua`, `frames/dungeonjournal/dungeonjournal.lua`, `frames/dungeonjournal/dj_map.lua`, `frames/map/pins.lua`, `frames/map/providers/pins_dungeonjournal.lua`, `frames/map/providers/pins_recipes.lua`, `frames/map/providers/pins_camelot_quests.lua`, `frames/professions/sources.lua`, `frames/professions/contacts.lua`, `frames/gear/highest.lua`, `frames/gear/highest/validator.lua`, `frames/gear/highest/tooltips.lua`, `core/items.lua`)**:
  - moved unfiltered dungeon sidebar upgrade counting onto an incremental `3`-dungeon-per-tick queue, raised gear/item stat evaluation caches (`1500`-`3000`), and skipped retail-only embellishment tooltip scans on classic/camelot.
  - added lazy per-map spatial indices for dungeon entrances, dungeon quests, and unlearned profession recipes, skipped fallback recipe source text queries during spatial indexing, gated sleeping-bag scans to relevant maps, suppressed world map pin providers while the dungeon overlay is shown, and deduplicated floor texture assignments.
- **quest objective reward tooltips, paladin seal tracking & theme loading (`frames/quests/helpers/q_tooltip.lua`, `frames/tracking/auras.lua`, `frames/tracking/tracking_camelot.lua`, `sfui.toc`)**:
  - restored quest objective tooltip item rewards across classic/camelot and retail quest log signatures with live hover refresh on asynchronous item/quest data loads (`frames/quests/helpers/q_tooltip.lua`).
  - tightened camelot paladin seal cast-aura tracking and harmful-aura filtering (`frames/tracking/auras.lua`, `frames/tracking/tracking_camelot.lua`) and enabled `frames/themes/modern.lua` across all client game types in `sfui.toc`.
