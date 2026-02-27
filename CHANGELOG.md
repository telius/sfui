## v0.3.0 (2026-02-26)

### Features
- **Spec-Specific Panels**: Cooldown panels are now saved and loaded based on the player's active specialization.
- **Forced CooldownViewer Saving**: Added programmatic save triggers for Blizzard's CooldownViewer when modifying Tracked Bars to prevent UI state loss.
- **Reload UI Prompt**: Added a user prompt to reload the UI after modifying Tracked Bars to ensure changes are applied correctly.

### Improvements
- Converted `cdm.lua` to LF line endings for better cross-platform compatibility.
- Added various performance optimizations and safety checks in `cdm.lua`.
