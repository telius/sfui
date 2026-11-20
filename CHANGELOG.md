# changelog

## v1.152 (2026-11-20)

### new features & improvements

- **gear manager option c redesign & resistance dock (`frames/gear/gear.lua`, `frames/gear/gear_camelot.lua`, `frames/gear/engine.lua`, `frames/gear/highest.lua`, `frames/gear/highest/validator.lua`, `frames/gear/highest/executor.lua`, `frames/themes/engine.lua`)**:
  - redesigned the classic/camelot gear manager with a persistent quick-action dock (roles, 5 camelot-atlas resistance buttons with max-resist badges, naked toggle, and `pve`/`pvp`/`auto` controls) that stays usable while collapsed, paired with a collapsible config drawer containing wider set dropdowns, slot locks, an `off-armor` toggle, live resist readout, and stat priorities.
  - clicking any resistance element equips maximum available resistance gear (with enchant and classic random-suffix support, 2h vs 1h+shield solving, unique-equipped deduplication, and normal-gear fallback on 0-resist slots) and locks auto-equip until disabled or another mode is selected; right-clicking opens upgrades filtered to that school.
- **gear upgrades resistance filters, crafted & tsm ah sources (`core/items.lua`, `frames/gear/upgrades.lua`)**:
  - added 5 elemental resistance filters (`fire`, `nature`, `frost`, `shadow`, `arcane`) with an `any armor` toggle, live equipped resistance readout, crafted item indexing (auto-enabled in resist mode), and optional tsm auction house buyout indexing with a gold-cap selector.
- **unified adventure guide tabs (`frames/dungeonjournal/dungeonjournal.lua`, `frames/gear/upgrades.lua`, `frames/professions/browser.lua`, `frames/fishing/fishing_atlas.lua`)**:
  - integrated `upgrades`, `recipes`, and `fishing` directly into the adventure guide tab bar alongside `dungeons` and `raids` with batch wishlist support.

### bug fixes & performance

- **flight timer cpu & memory overhaul (`frames/bars/flighttimer.lua`, `frames/options/tabs/tab_bars.lua`)**:
  - eliminated per-frame polling overhead and table churn using duration-bar / event-driven updates and pooled flight state.
- **minimap overlay, scoring & codebase standardization (`frames/map/overlay.lua`, `frames/gear/highest/scorer.lua`, `frames/gear/highest/solvers.lua`, `core/safety.lua`, `common.lua`, `frames/quests/modules/q_abundance.lua`)**:
  - reduced steady-state allocations and ticker overhead in the minimap overlay, refined protection/classic stat weights and item stat parsing, and standardized safety, font, and widget helpers across core and frame modules.
