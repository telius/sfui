# changelog

## v1.155 (2026-11-24)

### new features & improvements

- **camelot cave map overlays (`sfui_overlay_maps/data/overlay_maps_camelot.lua`, `sfui_overlay_maps/media/`, `frames/map/overlay.lua`, `scripts/generate_overlay_poc.py`)**:
  - added baked camelot cave minimap overlay tiles and area-sorted unmapped cave lookup so smaller nested caves resolve cleanly over larger enclosing zones.
- **multi-account sync compression & protocol optimization (`frames/sync/codec.lua`, `frames/sync/merge.lua`, `frames/sync/sync.lua`, `frames/sync/hud.lua`)**:
  - added native `C_EncodingUtil` cbor + deflate + base64 wire compression (`2~` / `3~`) with backward-compatible fallback, safe unsent-snapshot queue coalescing, single-encode multi-channel fanout, and ordered throttle retry/backoff across addon and battle.net channels.
  - stripped quest tables from `DATA_ALT` with signature-based no-op skip, switched live vendor/trainer/drop/quest contact updates to single-entry `DELTA_CONTACT` packets, added hash-based `DATA_MAIL` manifest reconciliation, removed redundant outbound `deep_copy` allocations, added instant `DATA_ACTIVE_QUESTS` and multibox hud pushes on synced party join, suppressed non-join roster `HELLO` bursts, and backed off idle solo quest-sync ticks to 20s.
- **quest sync tracker & tooltip completion clarity (`frames/quests/helpers/q_common.lua`, `frames/quests/helpers/q_tooltip.lua`, `frames/quests/modules/q_camelot.lua`, `frames/quests/modules/q_camelot_class.lua`, `frames/quests/modules/q_quests.lua`, `frames/sync/merge.lua`, `frames/sync/sync.lua`)**:
  - added monotonic quest-delta revision checks, pure active-quest digest recovery (`DATA_ACTIVE_QUESTS`), party-vs-battle.net broadcast deduplication, derived completion when all objectives finish, `(all complete)` collapsed tags and clear peer completion/progress lines in the objective tracker, canonical forever party unit caching with unit/object tooltip completion synthesis, and shared per-refresh peer snapshots across tracker modules and tooltips.
- **classic gear scoring & armor validation (`frames/gear/highest.lua`, `frames/gear/highest/scorer.lua`, `frames/gear/highest/tooltips.lua`, `frames/gear/highest/validator.lua`, `frames/gear/upgrades.lua`)**:
  - tuned classic/forever armor subclass tiebreakers by role (healer, tank, melee dps), smoothed the level 40+ mail/plate transition while keeping holy paladin armor unrestricted, exempted future-unlock armor red tooltip text during lookahead checks, and invalidated gear validation caches on skill line updates.

### bug fixes & reliability

- **sync handshake & queue hygiene (`frames/sync/sync.lua`, `frames/sync/codec.lua`)**:
  - gated tracked-skill and pinned-recipe force broadcasts strictly to manifest handshakes so targeted quest `WANT` pulls no longer re-blast skills and pinned recipes.
  - isolated inbound chunk reassembly buffers per channel and bounded `FlushQueue` under persistent throttle.
