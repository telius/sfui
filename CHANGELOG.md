# changelog

## v1.126 (2026-10-30)

### improvements & bug fixes

- **death knight rune responsiveness (`frames/bars/bars.lua`)**:
  - removed the 50ms hard-drop event throttle on `RUNE_POWER_UPDATE` so multi-rune spenders and simultaneous rune procs update immediately without dropping events.
  - added an on-demand 50fps (`0.02s`) `OnUpdate` loop (`rune_bar_on_update`) on `rune_bar` that activates only while at least one rune is recharging and detaches (`SetScript("OnUpdate", nil)`) as soon as all 6 runes are ready, smoothly animating recharging runes with zero idle overhead.
  - guarded `sfui.trackedbars.ForceLayoutUpdate()` inside `update_rune_bar` so layout updates only run when the rune bar dimensions actually change.

- **blizzard objective tracker raid wipe suppression (`frames/quests/engine/q_tracker.lua`)**:
  - added a `SetAlpha` post-hook and `OnShow` script hook on `ObjectiveTrackerFrame` inside `SuppressBlizzardTrackers()` to immediately clamp alpha back to `0` whenever `ManagedFrameContainerMixin:AnimInManagedFrames()` (on `UI.TopLevelParentShown` after raid wipe fade-ins or cutscenes) or third-party boss mods restore its alpha to `1`.
  - registered `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`, `CINEMATIC_STOP`, `STOP_MOVIE`, and delayed `ENCOUNTER_END` suppression passes in `SetupEventRouting()`.
