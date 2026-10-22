# changelog

## v1.119 (2026-10-22)

### improvements & bug fixes

- **combat telemetry theme backdrop occlusion fix**:
  - resolved frame level inversion where themed container backdrops in `oldgod`, `fallensanctum`, `maw`, and `necrolord` themes occluded scrollable text in combat telemetry (`frames/themes/engine.lua`, `frames/character/infopanel.lua`, `frames/themes/oldgod.lua`, `frames/themes/fallensanctum.lua`, `frames/themes/maw.lua`, `frames/themes/necrolord.lua`).
  - properly elevated content containers, scroll frames, scroll children, and telemetry rows above container decoration layers.
  - parented telemetry subtitle to an elevated overlay frame to prevent occlusion by outer window backdrops (`frames/character/infopanel.lua`).

- **camelot talent known resolver flyout fix**:
  - fixed a load-order issue where `CheckFlyoutSlot` captured an uninitialized nil reference in `core/talents_camelot.lua`, resolving nil call errors on `PLAYER_TALENT_UPDATE`, `Msg:SFUI_SPEC_CHANGED`, and `SPELLS_CHANGED` (`core/talents_camelot.lua`, `frames/reminders/buffs_data.lua`).
