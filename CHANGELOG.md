# Changelog

## v1.95 (2026-10-12)

### features

- **unified map pin provider architecture**: migrated all map pins (dungeon entrances, library books, recipe vendors, and camelot quests) into a single engine in `frames/map/pins.lua` with modular providers in `frames/map/providers/` and centralized map utilities in `core/map.lua`. retired legacy duplicate pin scripts.
- **auto-repair safety threshold**: added a 5,000g safeguard in `frames/automation/automation.lua` that intercepts and blocks auto-repairs when the bill exceeds 5,000 gold, alerting the player via an on-screen warning dialog and chat message to prevent loss of funds from blizzard's item scaling repair bugs.
- **merchant currency display**: updated the merchant currency bar in `frames/merchant/merchant_utility.lua` to format money with a single gold icon followed by comma-separated denominations (`[gold] [g],[s],[c]`).
- **cooking & secondary profession catalogue**: expanded recipe browser support in `frames/professions/browser.lua` and `frames/professions/filters.lua` to include cooking and secondary skills even when the character has not yet learned the profession.

### improvements & bug fixes

- **c++ crash prevention & frame pooling**: eliminated `SetParent(nil)` frame orphaning across `frames/portals/portals.lua`, `frames/alts/alts.lua`, and `frames/tracking/trackedbars.lua`, reparenting recycled frames safely to `UIParent` to prevent game client access violation crashes.
- **keybind repeat debounce**: added 0.15s input throttles to `sfui.portals.Toggle`, `sfui.alts.Toggle`, `sfui.dungeonjournal.Toggle`, and `sfui.recipes.ToggleBrowser` to eliminate client lockups from high-frequency key repeat spam.
