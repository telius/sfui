## v0.3.0f (2026-02-27)

### Features
- **Vehicle UI**: Massive aesthetic overhaul matching `trackedicons`. Complete with cooldown sweeps, stack texts (counts), and shadow desaturation effects. Uses highly performant event-based refreshes rather than an `OnUpdate` loop.
- **Auto Compare**: Repositioned the Auto Compare toggle directly under Ring Cursor in options and removed over-complex logic like the shift-to-disable hotkey to streamline the feature.
- **Event Dispatcher**: Centralized all `OnEvent` and `OnUpdate` handlers into a unified dispatcher in `common.lua`. This significantly improves technical debt and performance. Fixed Lua errors (`compare string with number`). `sfui.events.RegisterUpdate` is now polymorphic.
- **Improved Performance**: Reduced CPU and memory overhead during active gameplay by eliminating redundant frame allocations and event registrations.

### Bug Fixes
- **UI Tweaks**: Renamed Research node T1180 to "Void Research".
- **Power Bars**: Fixed DK runebars (and auxiliary power bars) forcefully showing themselves out of combat, allowing them to correctly follow healthbar visibility rules.
- **Options UI**: Fixed a Lua error (`SetSize`) when opening the Minimap options panel, caused by a tooltip/width argument mismatch in the slider component.
