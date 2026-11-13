# changelog

## v1.148 (2026-11-13)

### new features & improvements

- **camelot spellbook trainer, flight timer & world map utilities (`frames/character/trainer.lua`, `frames/bars/flighttimer.lua`, `data/flight_camelot.lua`, `frames/map/zonelevels.lua`, `frames/map/gatherskill.lua`, `frames/options/tabs/tab_minimap.lua`, `sfui.toc`)**:
  - added an integrated spellbook trainer and unlearned rank browser for camelot/forever (`frames/character/trainer.lua`).
  - added a self-calibrating taxi flight timer bar with multi-hop intermediate stop ticks, learned leg durations, and an early-landing request button (`frames/bars/flighttimer.lua`, `data/flight_camelot.lua`).
  - added world map cursor zone level and fishing skill readouts (`frames/map/zonelevels.lua`) plus color-coded gathering skill requirements on herb, ore, and skinning tooltips (`frames/map/gatherskill.lua`).
- **alts ruleset classification, spell upranking & automation upgrades (`frames/alts/alts.lua`, `frames/alts/alts_camelot.lua`, `frames/automation/rankup.lua`, `frames/automation/logs.lua`, `frames/automation/automation.lua`, `frames/hide.lua`, `frames/ring/ring_secure.lua`)**:
  - fixed camelot character ruleset classification and expanded alt roster, mail, and recipe tracking (`frames/alts/alts.lua`, `frames/alts/alts_camelot.lua`).
  - upgraded spell upranking with `IsSpellBookItemLowRank`, action bar slots `1-180`, and pet action bar rank upgrades (`frames/automation/rankup.lua`).
  - added modifier-variant secure keybindings on the radial ring (`frames/ring/ring_secure.lua`), smart instance combat-log toggling (`frames/automation/logs.lua`), `SellAllJunkItems()` retry handling (`frames/automation/automation.lua`), and taint-safe `UIErrorsFrame:SetMessageTypeEnabled` filtering (`frames/hide.lua`).

### bug fixes & codebase hardening

- **cdm buff stacks, combat aura resolution & secret-value safety (`frames/tracking/buffs.lua`, `frames/tracking/auras.lua`, `frames/tracking/icon_aura.lua`, `frames/tracking/trackedbars.lua`, `frames/tracking/glows.lua`, `frames/gear/lootviewer.lua`, `frames/bars/soulfragments.lua`)**:
  - raised `Applications` frame levels above `Cooldown` swipes and enforced outlined stack text on socketed and preview tracked buffs (`frames/tracking/buffs.lua`).
  - restored combat buff stack display across tracked icons and bars via `ShouldSpellAuraBeSecret`-guarded `GetPlayerAuraBySpellID` queries, `GetApplicationsFontString()` fallbacks, `appsAuthoritative` cast-prediction flags, secret aura table guards, and non-destructive module namespace initializers.
- **codebase slimming, deduplication & packaging cleanup (`.pkgmeta`, `.luacheckrc`, `README.md`, `data/dj_maps_camelot.lua`, `frames/actionbars/bind.lua`, `frames/merchant/merchant.lua`, `frames/themes/engine.lua`)**:
  - excluded raw scraper and dev json datasets from release archives in `.pkgmeta`, removed duplicate nested `LibStub` files under `Libs/LibCustomGlow-1.0`, deduplicated camelot map/trainer helpers and shared backdrops, and expanded `.luacheckrc` static analysis across all 238 lua files.
