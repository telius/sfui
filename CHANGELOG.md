# Changelog

## v2.01 (2026-10-15)

### features

- **ring radial menu engine**: added full radial wheel system with secure action execution, controller/keyboard/mouse support, smooth entry/exit animations, and dedicated configuration tab (`frames/ring/ring.lua`, `frames/ring/ring_geometry.lua`, `frames/ring/ring_live.lua`, `frames/ring/ring_secure.lua`, `frames/ring/ring_view.lua`, `frames/options/tabs/tab_ring.lua`).
- **modular ring providers**: integrated built-in rings for player specializations (`frames/ring/providers/ring_specs.lua`), target/world markers (`frames/ring/providers/ring_markers.lua`, `frames/ring/providers/ring_worldmarkers.lua`), professions (`frames/ring/providers/ring_professions.lua`), quest items (`frames/ring/providers/ring_questitems.lua`), tracking options (`frames/ring/providers/ring_tracking.lua`), and utility tools (`frames/ring/providers/ring_utility.lua`).
- **taint-free square minimap**: implemented engine-level square mask (`130937`) with global `GetMinimapShape` hook for community addons, circular clutter suppression without frame hiding, hybrid indoor cave map support, and 1px themed border (`frames/map/square.lua`).
- **customizable minimap dimensions & positioning**: added fine-grained width and height sliders, screen anchor point selection, and offset controls with instant layout recalculation (`frames/map/minimap.lua`, `frames/options/tabs/tab_minimap.lua`).
- **delve & labyrinth boons tracker**: implemented dynamic buff display panel for delve and labyrinth powers (`1280098`), detailing accumulated stacks, abilities, and stat enhancements with automatic sizing below the delve hud and quest tracker (`frames/quests/helpers/q_boons.lua`, `frames/options/tabs/tab_objectives.lua`, `frames/quests/engine/q_layout.lua`, `frames/quests/engine/q_tracker.lua`, `frames/quests/q_mythic.lua`).

### improvements & bug fixes

- **pet bar performance & responsiveness**: decoupled pet bar updates into throttled tick updates (`RequestPetBarUpdate`), dedicated cooldown (`UpdatePetCooldowns`), usability (`UpdatePetUsable`), and hotkey (`UpdatePetHotkeys`) routines with precomputed key caches to prevent combat stutter (`frames/actionbars/bars.lua`).
- **action bar mouseover grid caching**: passed cached configuration blocks during mouseover drag state updates to eliminate redundant database queries across all action slots (`frames/actionbars/mouseover.lua`).
- **portal interaction refinements**: enhanced mouseover responsiveness and backdrop feedback on portal buttons (`frames/portals/portals.lua`).
- **keybinding declarations**: registered ring toggles and radial wheel controls for retail and classic/camelot clients (`Bindings.xml`, `Bindings_Standard.xml`, `Bindings_Camelot.xml`).
