# changelog

## v1.150 (2026-11-19)

### new features & improvements

- **arpg minimap overlay & full-world architectural map pack (`frames/map/overlay.lua`, `frames/map/square.lua`, `frames/map/minimap.lua`, `frames/map/pins.lua`, `frames/map/indicators.lua`, `frames/map/buttons.lua`, `frames/map/location.lua`, `frames/map/status.lua`, `frames/options/tabs/tab_minimap.lua`, `frames/mem.lua`, `commands.lua`, `Bindings_Camelot.xml`, `sfui_overlay_maps/sfui_overlay_maps.toc`, `sfui_overlay_maps/data/overlay_maps_camelot.lua`)**:
  - added a centered arpg-style transparent minimap overlay (`/sfoverlay` and camelot keybinding) with radial edge feathering, automatic minimap rotation, in-combat toggling and opacity dimming, blocking-panel auto-hide, `alt+scroll` zoom and `alt+shift+scroll` opacity controls, directional waypoint and corpse edge chevrons, active-only quest objective pins, and instance native-minimap fallback.
  - bundled the `sfui_overlay_maps` on-demand map pack covering eastern kingdoms, kalimdor, ironforge, undercity, and 42 caves, crypts, and pre-instance micro-maps (`1280` `blp2 dxt5` contour, hatch, and wmo wall tiles plus `1200` subzone mappings).
- **bundled `sfuibug` error inspector & stack diagnostics (`sfuibug/sfuibug.lua`, `sfuibug/sfuibug.toc`, `.pkgmeta`)**:
  - bundled `sfuibug` `v1.1` directly into `sfui` releases alongside `sfui_overlay_maps`, adding `/sfuibug inspect` (`shift-left-click` minimap icon), callstack, argument, and local capture, secret-table guards, and `overlay` / `sfui_overlay_maps` module attribution.
- **action bar low-rank spell badges & camelot spell/druid helpers (`frames/actionbars/bars.lua`, `frames/actionbars/style.lua`, `frames/options/tabs/tab_actionbars.lua`, `frames/automation/rankup.lua`, `common.lua`, `config.lua`)**:
  - added optional low-rank spell badges on action bar buttons alongside camelot custom druid bear-form and highest-rank spell checks (`common.lua`, `frames/actionbars/style.lua`, `frames/automation/rankup.lua`).

### bug fixes & performance

- **buff tracking secret guards, multibox sync & camelot data refresh (`frames/tracking/buffs.lua`, `frames/bars/soulfragments.lua`, `frames/sync/multibox.lua`, `frames/sync/sync.lua`, `data/recipes_camelot.lua`, `data/fishing_camelot.lua`, `data/dj_camelot.lua`)**:
  - hardened `frames/tracking/buffs.lua` secret-value guards and fallback icon socketing, improved cross-shard and project checks in `frames/sync/multibox.lua` and `frames/sync/sync.lua`, and refreshed camelot recipe, fishing, and dungeon journal data tables.
