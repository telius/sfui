# changelog

## v1.134 (2026-11-04)

### features & improvements

- **wow forever dungeons, dalaran attunement & map pins (`data/dj_camelot.lua`, `frames/alts/alts_camelot.lua`, `frames/dungeonjournal/dj_bosses.lua`)**:
  - added a `dalaran attune` row to `frames/alts/alts_camelot.lua` tracking the city of dalaran attunement questlines for both alliance (`92432` *an alarming request* → `92458` *heart of disruption* → `92459` *friend of the kirin tor*) and horde (`544` *prison break in* & `93680` *key to the city* → `545` *dalaran patrols* → `92434` *blood in the streets* → `96984` *heart of disruption* / item `277507` *dalaran sewer key*), including live `in progress` status and faction-aware tooltips.
  - added full step-by-step world map quest chain pins and coordinates in `data/dj_camelot.lua` for the alliance and horde city of dalaran attunement chains as well as all open-world quest givers for city of dalaran and excavation site: wetlands.
  - updated level ranges in `data/dj_camelot.lua` for ruins of lordaeron (`15 - 20`), the drowned city (`35 - 40`), kroldok stronghold (`40 - 45`), alcaz prison (`48 - 53`), blackmaw hold (`55 - 60`), and shaper's terrace (`58 - 60`) to match official forever dungeon tuning.
  - updated `frames/dungeonjournal/dj_bosses.lua` so recipe scroll boss drops display required profession `skill <minSkill>` instead of their scroll `ilvl`.
- **camelot / forever recipe database & profession sources (`data/recipes_camelot.lua`, `frames/professions/sources.lua`, `frames/professions/filters.lua`, `frames/professions/progress.lua`, `frames/reminders/buffs_consumables.lua`, `scripts/sync-recipes.py`)**:
  - updated `scripts/sync-recipes.py` and regenerated `data/recipes_camelot.lua` (`1,945` forever recipes) so craft spells derive authoritative required skill (`minSkill`) from wowhead forever `learnedat` / `skillup` thresholds or matching recipe scroll `reqskillrank`, link exact `recipeItemID` scroll items, and exclude season of discovery (`sod`) recipes.
  - mapped renamed and uncategorized forever craft spells (such as `elixir of sages`, `greater mageblood elixir`, `lesser mageblood elixir`, `greater cleric's elixir`, `elixir of the phalanx`, `elixir of wicked regeneration`, and `minor protection potion`) to their professions and added forever elixirs to `frames/reminders/buffs_consumables.lua`.
  - synchronized `LIMITED_RECIPE_ITEMS`, `LIMITED_RECIPE_VENDORS`, and `RECIPE_DROP_NPCS` in `frames/professions/sources.lua` with forever recipe item ids and added vendor-name deduplication when merging curated and wowhead vendor sources.
  - added craft-output item fallback resolution in `frames/professions/filters.lua` and `frames/professions/progress.lua` so the trade skill window `ilvl` badge and progress summary resolve equipment item levels even before the wow client caches a recipe's output item link.
- **staggered wowhead data sync pipeline (`scripts/sync_core.py`, `scripts/sync-data.py`, `scripts/sync-recipes.py`, `scripts/sync-dj-loot.py`, `scripts/sync-fishing.py`)**:
  - added thread-safe request pacing with jitter and lowered default concurrency across `scripts/sync_core.py`, `scripts/sync-recipes.py`, `scripts/sync-dj-loot.py`, and `scripts/sync-fishing.py`, plus a `--skip-zones` flag in `scripts/sync-data.py` so orchestrated runs discover zones once and reuse the cache across sub-stages.
