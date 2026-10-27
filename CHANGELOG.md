# changelog

## v1.123 (2026-10-27)

### features

- **cursor ring 144hz mode & performance optimizations (`frames/cursor.lua`, `frames/ring/ring_live.lua`, `dispatcher.lua`, `frames/options/tabs/tab_main.lua`, `frames/mem.lua`)**:
  - added toggle in `tab_main` to enable optional 144hz mode for cursor ring (`SfuiDB.cursorRing144hz`, disabled by default).
  - lowered dispatcher `MIN_UPDATE_INTERVAL` floor to 0.005s (~200fps) to support high-refresh cursor updates.
  - restored stationary cursor guard in `ring_live.lua` and pixel deadband rounding in `cursor.lua` to eliminate redundant redraws and scale calculations.
  - added active refresh rate indicator in memory profile viewer.

- **core module taxonomy & pooling utilities (`core/module.lua`, `core/pool.lua`)**:
  - added `object_pool` and `window_pool` utilities in `core/pool.lua`.
  - added `objectives` and `automation` categories in `core/module.lua`.

### improvements & bug fixes

- **combat visibility & hide out of combat fixes (`common.lua`, `frames/tracking/trackedicons.lua`)**:
  - synchronized `sfui.common.is_in_combat()` with `InCombatLockdown()` and `UnitAffectingCombat("player")` as authoritative fallbacks, preventing rest area / city target dummy combat from being evaluated as out of combat.
  - registered `UNIT_FLAGS` and `PLAYER_FLAGS_CHANGED` listeners and added combat state transition edge detection in `_OnTrackedIconsUpdate`.
  - gated `hideMounted` and `hideInVehicle` icon early-exits behind combat verification so travel forms or mounted combat do not hide icons.
  - scoped warrior stance panel form matching strictly to classic builds.

- **blizzard cooldown viewer offscreen parking (`common.lua`)**:
  - moved blizzard cooldown viewer frames offscreen cleanly using native anchor methods to prevent phantom mouseover tooltips without tainting secure frame tables.
