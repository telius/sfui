# Changelog

## v1.91 (2026-10-11)

### features

- **static recipe database virtualization**: optimized the authoritative recipe database (`data/recipes_camelot.lua`) via `scripts/sync-recipes.py`. serialized all 2,344 crafting recipes into compact flat tuples and wrapped them in an on-demand metatable lazy decoder (`decodedCache`), eliminating over 7,000 upfront table allocations at startup.
- **skill tier color pooling**: deduplicated 4-threshold progression color tables into a shared `COLOR_POOL`, reducing redundant array allocations across the catalog.
- **streaming catalog iterator**: added `sfui.recipes_camelot.IterateRecipes()` to allow complete recipe traversal without bulk-instantiating all 2,344 table dictionaries into memory.

### improvements & bug fixes

- **combat text secret value taint fix**: fixed a fatal error in `frames/experience/events.lua` (`attempt to compare local 'val' (a secret number value, while execution tainted by 'sfui')`) triggered during reputation gains. removed the redundant `COMBAT_TEXT_UPDATE` listener to adhere strictly to sfui's zero-secret-interaction design principle, relying cleanly on `CHAT_MSG_COMBAT_FACTION_CHANGE`.
- **massive memory & footprint reduction**: reduced `data/recipes_camelot.lua` file size by 51% (424 kb down from 872 kb) and line count from 29,913 to 8,135 lines (-73%), cutting live lua heap overhead by ~46%.
- **instant O(1) telemetry**: updated `sfui.recipes_debug_info()` in `frames/professions/browser.lua` to read pre-computed `num_recipes` directly without looping `pairs()`.
