# changelog

## v1.115 (2026-10-19)

### improvements & bug fixes

- **combat memory churn & spike reduction**:
  - radial ring bag-scan elimination: removed heavy bag-scanning and quest item rebuilds during combat entry, preventing ~280kb memory spikes (`frames/ring/ring.lua`, `frames/ring/providers/ring_questitems.lua`).
  - tracked icons aura caching & combat throttle: cached aura applications and missing states so player auras only re-evaluate on dirty events instead of per-frame, and throttled combat icon state processing (`frames/tracking/trackedicons.lua`).
  - target bar allocations & duplication: added target guid caching for quest objectives and unit names, cached creature difficulty colors, and deduplicated redundant updates on target acquisition (`frames/bars/target.lua`).
  - pet bar state driver caching: cached generated visibility macro driver strings to prevent re-compilation churn on target changes (`frames/bars/pet.lua`).
  - tracked bars combat event throttling: enforced a 0.25s combat throttle on sync and events to stabilize memory during high-frequency aura churn (`frames/tracking/trackedbars.lua`, `frames/quests/helpers/q_boons.lua`).
  - options ui: refreshed checkbox state handlers and icon assets (`frames/options/tabs/tab_fishing.lua`, `frames/options/tabs/tab_rings.lua`).
