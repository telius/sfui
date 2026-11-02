# changelog

## v1.130 (2026-11-02)

### features & improvements

- **fishing atlas, hud & camelot waters database (`frames/fishing/fishing_atlas.lua`, `frames/fishing/fishing_hud.lua`, `frames/automation/fishing.lua`, `data/fishing_camelot.lua`, `frames/sync/merge.lua`, `frames/sync/sync.lua`)**:
  - added the fishing atlas ui with species catalog, waters & zones breakdown (organized into eastern kingdoms and kalimdor continent sections with filter pills), pools & schools guide, and lures & milestones tracker.
  - synced 58 camelot / classic forever waters (including custom forever zones `zephras isle`, `riverglades`, `mount hyjal`, `shen'dralas`, and 9 fishable dungeons), sub-zone skill & habitat overrides (`coastal`, `inland`, `oasis`), and runtime fallback discovery for newly caught in-game fish and unindexed zones.
  - added cross-account fishing ledger synchronization (`DATA_FISHING`, `DELTA_FISHING_CATCH`) and consolidated shared helper functions across all fishing modules.
- **unified zero-knowledge data synchronization pipeline (`scripts/sync-data.py`, `scripts/sync-data.sh`, `scripts/sync_core.py`, `scripts/sync-dj-loot.py`, `scripts/sync-recipes.py`, `scripts/sync-fishing.py`, `data/forever_zones.json`, `data/dj_camelot.lua`, `data/recipes_camelot.lua`, `data/fishing_camelot.lua`)**:
  - unified zone, dungeon journal, profession recipe, and fishing synchronization into a single runner (`scripts/sync-data.sh`) with shared wowhead waf token caching and rate-limit pacing.
  - added automatic zero-knowledge self-discovery of newly added wowhead forever outdoor zones (`uiMapId`, level brackets, continent, fishing skill tiers), dungeon encounters & loot tables from official dungeon overview guides, custom recipes, and custom fish species.
- **experience & reputation bar height defaults (`config.lua`, `frames/experience/bar.lua`, `frames/experience/reputation.lua`, `frames/experience/experience.lua`, `frames/options/tabs/tab_experience.lua`)**:
  - updated the default height of both the experience and reputation status bars to `8px` with automatic migration (`_expDefaultsV5`) for existing profiles.
