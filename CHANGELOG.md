# changelog

## v1.114 (2026-10-19)

### improvements & bug fixes

- **complete gamepad manipulation removal**:
  - completely removed all gamepad action bar and pet flyout hooks, hierarchy disarming, mixin overrides, and event registrations (`compat.lua`, `frames/actionbars/actionbars.lua`).
  - removed gamepad vibration cvar handling and controller bind listeners (`frames/automation/fishing.lua`, `frames/options/tabs/tab_fishing.lua`, `core/widgets.lua`).
  - eliminated secure execution taint and protected function blocking (`HideBase`, `SetFrameStrata`, `SetShown`) during combat.
