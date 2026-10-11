# Changelog

## v1.90 (2026-10-11)

### features

- **recipe catalog & source database (camelot / classic)**: comprehensive in-game crafting recipe browser, source lookup, and completionist tracker (`/sfui recipes` or `/recipe`). includes extensive baseline database (`data/recipes_camelot.lua`) with trainers, vendors, quest rewards, limited supply items, and creature drops. modularized into clean subsystems across `frames/professions/` (`sources.lua`, `contacts.lua`, `tooltips.lua`, `filters.lua`, `progress.lua`, `rows.lua`, `browser.lua`, `pins.lua`).
- **world map recipe pins**: added interactive pins on the world map canvas for unlearned recipes currently available to the character's skill rank (`frames/professions/pins.lua`). clusters multi-recipe sources with count badges, color codes by source type (vendor, trainer, quest, drop), and integrates a toggle into the native world map tracking dropdown menu.
- **objective tracker shopping list**: pinned recipes now track real-time reagent bag counts (`frames/quests/modules/q_camelot_recipes.lua`), displaying a status badge (`[ready]` vs `[recipe]`), acquisition coordinates, and left-click routing directly into the recipe catalog.
- **cross-character alt network & shopping filter**: added `alt needs` filter and item badges (`[alt]`) to identify recipes needed by other characters on the realm (`frames/professions/filters.lua`, `frames/alts/recipes.lua`).
- **merchant & dungeon journal deep linking**: added a `catalog` button on the merchant utility bar (`frames/merchant/merchant_utility.lua`) to inspect vendor recipes, and deep-linked dungeon drop recipes directly to boss encounter pages in the dungeon journal (`frames/dungeonjournal/dungeonjournal.lua`, `frames/dungeonjournal/dj_bosses.lua`).
- **theme & progress bar integration**: connected completionist progress bar textures to `config.lua` (`barTexture`) with dynamic theme updates (`frames/themes/engine.lua`). replaced text waypoints with blizzard's native square raid target icon (`UI-RaidTargetingIcon_6`).
- **diagnostics & memory profiler**: registered real-time recipe catalog statistics, active filter status, and map pin counts in `frames/mem.lua`.

### improvements & bug fixes

- **clean sub-module architecture**: decoupled monolithic recipe browser into focused, non-circular modules (`filters.lua`, `progress.lua`, `rows.lua`, `browser.lua`, `pins.lua`).
- **skill bar tracker click routing**: left-clicking tracked crafting professions in the objective tracker (`frames/quests/modules/q_camelot_skills.lua`) now opens the recipe catalog pre-selected to that skill line.
