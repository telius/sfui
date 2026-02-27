## v0.3.0a (2026-02-27)

### Bug Fixes
- **Unavailable Spells (Icons)**: Fixed an issue where tracked icons for unlearned/unavailable spells were still displaying on the in-game UI despite being grayed out in the assignments list.
- **Minimap Autozoom**: Added a configurable delay to the minimap autozoom feature.
- **Vehicle UI Errors**: Fixed a Lua error related to tracked icons when entering/exiting vehicles.

## v0.3.0 (2026-02-26)
### Features
- **Spec-Specific Panels**: Cooldown panels are now saved and loaded based on the player's active specialization.
- **Forced CooldownViewer Saving**: Added programmatic save triggers for Blizzard's CooldownViewer when modifying Tracked Bars to prevent UI state loss.
- **Reload UI Prompt**: Added a user prompt to reload the UI after modifying Tracked Bars to ensure changes are applied correctly.

### Improvements
- Converted `cdm.lua` to LF line endings for better cross-platform compatibility.
- Added various performance optimizations and safety checks in `cdm.lua`.
