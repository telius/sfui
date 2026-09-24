# Changelog

## v12.1.0-53 (2026-09-24)

### Architectural Features & Telemetry
- **Universal Module Registry & Diagnostic Telemetry Across All 30 Subsystems (`frames/mem.lua`, `core/module.lua`)**:
  - Integrated `sfui.RegisterModule` lifecycle tracking and standardized `_debug_info` telemetry providers across all 30 addon subsystem modules (including `fishing`, `pets`, `logs`, `hammer`, `bonusroll`, `stats`, `gear`, `automation`, `currency`, `minimap`, `location`, `cursor`, `research`, `merchant`, `transfer`, `bars/vehicle`, `bars/soulfragments`, `tracking/cdm`, `tracking/glows`, `portals`, `gear/lootspec`, `quests/modules/q_worldevents`, `quests/q_mythic`).
  - Expanded `/sfui mem` diagnostic profiler to display live memory metrics, frame pools, table pools, and cache counts across the entire interface.
- **Centralized Dispatcher Update Loops & Zero-CPU Idle (`frames/mem.lua`, `frames/cursor.lua`, `frames/bars/bars.lua`, `frames/bars/vehicle.lua`)**:
  - Migrated legacy private frame `OnUpdate` loops to `sfui.events.RegisterUpdate`.
  - Memory Profiler GUI loop (1.0s) registers on `OnShow` and unregisters on `OnHide` (0 CPU when hidden).
  - Cursor ring position tracking loop registers on enable and cleanly unregisters when disabled.
  - Mount speed bar loop runs only while airborne during dragonriding / skyriding and sleeps when grounded.
  - Vehicle bar update loop hooks strictly to vehicle frame `OnShow` and unregisters on `OnHide`.

### Improvements & Documentation
- **Comprehensive Documentation & Feature Reference Overhaul (`README.md`)**:
  - Overhauled user documentation with detailed sections for the modular 14-tab options panel, companion pet manager, fishing automation, loot browser, objective tracker engine, and gear heuristics.
  - Added a full slash commands reference table and Blizzard keybindings mapping.
- **Single-Release Changelog Architecture (`CHANGELOG.md`, `version-bump.md`)**:
  - Streamlined `CHANGELOG.md` to retain only current active release patch notes, delegating historical version archives to Git releases.
