# changelog

## v1.110 (2026-10-18)

### features

- **modular architecture for highest gear engine**: refactored the complex gear scoring, validation, combinatorial solving, and equipment swapping pipeline in `frames/gear/highest.lua` into clean decoupled modules under `frames/gear/highest/`:
  - `frames/gear/highest/tooltips.lua`: fast cached tooltip scanning, stat weight extraction, and equipment heuristics.
  - `frames/gear/highest/validator.lua`: equipment eligibility rules, level checks, and two-handed slot validation.
  - `frames/gear/highest/scorer.lua`: dynamic item scoring, weapon dps priority for camelot hunters and classic/camelot retribution paladins, and retail two-handed specialization constraints.
  - `frames/gear/highest/solvers.lua`: dedicated single-slot, dual-wield, and ring/trinket pairing solvers.
  - `frames/gear/highest/executor.lua`: queued equip execution, equipment set synchronization, and post-swap telemetry.
  - `frames/gear/highest.lua`: lightweight event coordinator and options manager.

### improvements & bug fixes

- **recipe catalogue map waypoint tooltips**: fixed an uninitialized coordinate variable in `frames/professions/rows.lua`, restoring the click-to-waypoint super-tracking tooltip hint on catalogue rows.
- **immutable recipe source pool**: prevented coordinate data corruption in pooled source tables (`data/recipes_camelot.lua`) by shallow copying source records before injecting dynamic coordinates (`frames/professions/rows.lua`).
- **map pin shift-click waypoint navigation**: added missing shift-click handler in `frames/map/providers/pins_recipes.lua` to set super-tracked map waypoints directly from world map recipe pins.
- **metatable iteration safety**: replaced direct metatable pairs iteration with dedicated iterator helpers across `frames/professions/filters.lua`, `frames/professions/browser.lua`, and `data/recipes_camelot.lua`.
- **classic era recipe compendium support**: harmonized client load guards across all profession modules (`frames/professions/sources.lua`, `frames/professions/browser.lua`, `frames/professions/filters.lua`, `frames/professions/rows.lua`, `frames/professions/progress.lua`, `frames/professions/contacts.lua`, `frames/professions/tooltips.lua`) to enable the catalogue and `/recipes` slash commands on classic era.
- **curated and live source precedence**: prioritized curated and live vendor discoveries ahead of generic baseline entries in catalogue search and filtering routines (`frames/professions/filters.lua`).
- **memory diagnostics telemetry**: eliminated duplicate conflicting debug definitions in `frames/professions/browser.lua`, restoring full recipe telemetry in `/sfui mem`.
- **objective tracker recipe routing**: removed broken router override and resolved canonical profession names in tracker tooltips (`frames/quests/modules/q_camelot_recipes.lua`, `frames/professions/sources.lua`).
- **live trainer case-insensitive matching**: ensured live trainer skill lookups handle title-cased spell names without dropping training cost or skill requirements (`frames/professions/sources.lua`).
