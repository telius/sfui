# Changelog

## v1.97 (2026-10-14)

### features

- **patch 12.1.5 compatibility**: updated interface toc targeting patch 12.1.5 (`sfui.toc`) and resolved map canvas taint issues caused by blizzard protected function calls.
- **new cosmetic hearthstones**: cataloged new patch 12.1.5 hearthstones in `data/portals.lua` including hiveborn hearthstone (`281136`), shadeweaver's hearthstone (`281615`), naaru's embrace (`260221`), and classic deluxe dark portal (`184871`).
- **centralized waypoint engine**: consolidated all map pin and waypoint placements into `sfui.map.SetUserWaypoint` across dungeon journal (`frames/dungeonjournal/dj_quests.lua`, `frames/dungeonjournal/dungeonjournal.lua`), professions (`frames/professions/sources.lua`), and quest objective modules.
- **mythic+ tracker enhancements**: overhauled mythic+ objective blocks and keystone affixes display (`frames/quests/q_mythic.lua`) with refined layout, timers, and styling.

### improvements & bug fixes

- **map pin taint protection**: stubbed and guarded against protected button pass-through and click propagation methods (`SetPassThroughButtons`, `SetPropagateMouseClicks`, `SetPropagateMouseMotion`) in `core/map.lua` and `frames/map/pins.lua`.
- **quest objective tracker cleanup**: refactored quest tracker engine blocks, scenarios, and helper routines (`frames/quests/helpers/q_common.lua`, `frames/quests/modules/q_scenarios.lua`) to reduce code duplication and improve performance.
- **professions ui**: improved recipe progress bar display, filter states, and reagent source tooltips (`frames/professions/progress.lua`, `frames/professions/rows.lua`, `frames/professions/sources.lua`).
