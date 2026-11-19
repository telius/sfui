# changelog

## v1.151 (2026-11-19)

### new features & improvements

- **forever gear upgrade finder (`frames/gear/upgrades.lua`, `frames/gear/gear.lua`, `commands.lua`, `sfui.toc`)**:
  - added a standalone forever-only upgrade panel (`/sfupgrades`, `/upgrades`, `/sfui upgrades`, and `upgrades` button in the gear manager header) indexing dungeon journal boss drops/quests and questiedb open-world quests and vendors.
  - added a level-filter dropdown (`all equippable`, `equippable (-20 lvls)`, `lvl -20 to +4`, etc.), unrated trinket catalog mode (`ilvl` display without false `%` ratings, shown in `all slots` only when a trinket slot is empty), and per-character right-click hide/restore (`hidden` filter button).
- **minimal overlay compass & alt-hover map pin tooltips (`frames/map/compass.lua`, `frames/map/overlay.lua`, `frames/map/pins.lua`, `frames/options/tabs/tab_minimap.lua`)**:
  - added a minimal theme-aware overlay compass docked 2px above the xp bar stack with an opt-out toggle and mover support, plus `alt`-hover native map pin tooltips.
- **per-seal tracked bar colors (`config.lua`, `frames/tracking/tracking_camelot.lua`, `frames/tracking/trackedbars.lua`, `frames/tracking/trackedoptions.lua`)**:
  - added per-seal color customization when paladin seals are assigned as tracked bars in cdm.
- **forever dungeon journal maps (`data/dj_camelot.lua`, `data/dj_maps_camelot.lua`, `frames/dungeonjournal/dj_map.lua`, `media/dungeonmaps/UpperBlackrockSpireMap.tga`, `media/dungeonmaps/MapLinkArrow.tga`)**:
  - synced the upper blackrock spire map, link arrows, and camelot dungeon map data.
- **companion addon grouping & release sync (`sfui_overlay_maps/sfui_overlay_maps.toc`, `sfuibug/sfuibug.toc`, `scripts/weekly-release.py`)**:
  - added `## Group: sfui` to `sfuibug` and `sfui_overlay_maps` (plus icon metadata on `sfui_overlay_maps`) so both group cleanly under `sfui` in the addon list while remaining independent dependent sub-addons, and synced `sfui_overlay_maps/sfui_overlay_maps.toc` version bumps in `scripts/weekly-release.py`.
