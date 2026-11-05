# changelog

## v1.138 (2026-11-05)

### features & improvements

- **sync party hud theme & mover support (`frames/sync/hud.lua`)**:
  - registered `SfuiSyncPartyHUD` with `sfui.theme.RegisterWindow` (`cornerBrackets = true`) so it inherits the active theme's backdrop, borders, and corner brackets (`camelot`, `modern`, `oldgod`, `fallensanctum`, `maw`, `necrolord`) and live-updates on theme or palette changes.
  - styled the header accent bar, dividers, alternating row striping, hover highlights, and tooltips using the active theme palette and elevated child frames above decorative border layers.
  - registered `SfuiSyncPartyHUD` with `sfui.movers.Register` (`key = "syncpartyhud"`) for `/sfui move` edit mode support.
- **synced character quest objective progress (`frames/quests/helpers/q_common.lua`, `frames/quests/modules/q_camelot.lua`, `frames/quests/modules/q_camelot_class.lua`, `frames/quests/modules/q_quests.lua`, `frames/quests/helpers/q_tooltip.lua`, `frames/dungeonjournal/dj_quests.lua`, `frames/sync/merge.lua`, `frames/sync/sync.lua`)**:
  - quest tracker blocks now display live objective progress for all synced characters (`<char>: <objective>`, grouping characters with identical progress onto one line and hiding finished sub-objectives per character) alongside `! missing: <char>` and `ready: <char>`.
  - quests stay expanded in the tracker until all synced party members have completed their objectives, even after your own character reaches `Ready for turn-in`.
  - added combat-safe `DELTA_QUEST_PROG` active-quest delta broadcasts (`0.35s` debounce) so party objective updates sync in real time during combat and immediately refresh the tracker.
  - added active objective progress lines to the dungeon journal quest details panel and highlighted completed peer sub-objectives in green in quest tracker tooltips.
