## v0.2.18a (2026-02-26)

### Bug Fixes
- **Tracked Bars**: Re-anchored duration and stack text to the center of the bar. Removed all combat and secret-value restrictions to allow native Blizzard strings (like "150k" absorbs) to display correctly.

## v0.2.18 (2026-02-22)
### Features
- **Cursor Ring Scale**: Added a slider to the Main tab to scale the cursor ring (0.5x to 2.0x).
- **Class Forms Overhaul**: Overhauled cooldown panel management for Druid and Rogue forms with improved migration, deduplication, and resource updates.
- **Spec Color Override**: Added support for custom spec color overrides.

### Bug Fixes
- **Options UI (Sliders)**: Fixed a core issue where sliders would not persist their values to the database when dragged. They now correctly update the UI and save settings in real-time.
