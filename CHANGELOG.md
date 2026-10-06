# Changelog

## v12.1.0-77 (2026-10-07)

### features

- **experience & reputation bar**: complete native progression tracking module (`frames/experience/*`). features a multi-layer status bar with rested xp bonus overlays, completed quest turn-in previews, 20-segment tick dividers (classic 5% segments), and floating xp gain combat text.
- **dual & single bar progression modes**: supports independent stacked status bars for both xp and tracked reputation, or a single unified bar that automatically transitions to reputation, renown, friendship, or paragon progress upon reaching max level.
- **comprehensive reputation engine**: native tracking for standard faction standings, dragonflight / the war within renown tracks, classic / mop friendship ranks, and max-level paragon reward threshold bars.
- **rich informational tooltips**: detailed hover tooltips breaking down current/max progress, percentage, rested pool, remaining quests and kills to level, session gains, and leveling pace per hour.
- **experience options tab**: added dedicated configuration tab (`frames/options/tabs/tab_experience.lua`) supporting live bar dimensions, display modes, text formatting, and color customization.

### improvements & refactoring

- **slash command architecture**: streamlined command footprint in `commands.lua` to 3 essential slash commands: `/sfui [tab]` (with deep category routing), `/sfmem [gc]` (real-time telemetry and garbage collection), and `/rl` (quick ui reload). removed obsolete standalone commands (`/sffish`, `/sfpet`, `/sfql`, `/sfquestlog`, `/alts`, `/sfalts`, `/sftheme`, `/sfbarstyle`).
- **memory profiler & telemetry integration**: registered `experience` under `bars_combat` in `frames/mem.lua` with zero-allocation telemetry (`sfui.experience_debug_info()`), live frame recycler pool statistics (`GetPoolStats()`), and clean pool reset on disable.
- **theme synchronization**: statusbar textures dynamically synchronize with `sfui.bars:set_bar_texture` (`frames/bars/bars.lua`) and the global theme engine (`frames/themes/engine.lua`).
- **documentation**: redesigned `README.md` into a scannable, human-readable structure grouping modules into hud & combat, world & questing, quality of life & automation, and system & customization, while clearly documenting the central dispatcher architecture.
