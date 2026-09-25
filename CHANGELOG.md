# Changelog

## v12.1.0-55 (2026-09-25)

### Companion Pets Automation & Performance
- **Lean Pet Cycling & Management (`frames/pets.lua`, `frames/options/tabs/tab_pets.lua`)**:
  - Eliminated full 1,500+ pet journal indexing scans; focused rotation and pool construction exclusively on account favorites and character-specific assigned pets.
  - Fixed premature realm caching: `get_character_key()` now safely falls back to CVars and post-login realm names (e.g. `Silverlaine-Draenor`), preventing character favorites from being isolated in an empty profile.
  - Fixed direct Blizzard `C_PetJournal` API calls (`SummonPetByGUID`, `GetSummonedPetGUID`).
  - Added proactive pet presence verification to the 5.0s background loop and `PLAYER_ENTERING_WORLD`, guaranteeing companions are automatically summoned even while standing still in town.
  - Removed unnecessary instance and zone gating restrictions.

### Skyriding & Mount Speed Bar Fixes
- **Dynamic Mount Speed Bar Restoration (`frames/bars/bars.lua`)**:
  - Fixed Lua return-value truncation bug where `GetGlidingInfo()` was wrapped in parentheses, causing `forwardSpeed` to evaluate to `nil` and locking the speed bar at 100% white fill.
  - Added explicit zero-value initialization on status bar creation.
  - Restored real-time speed percentage updates, Thrill of the Skies magenta coloration, and 0-idle dispatcher unregistration when dismounted.

### City Flight & Zone Transition Optimization
- **Eliminated Subzone Memory Churn (`frames/quests/`, `frames/alts/`)**:
  - Unregistered `AREA_POIS_UPDATED` from World Events tracker, eliminating ~350 KB of garbage collection churn on every city subzone border crossing.
  - Gated background Alts synchronization behind frame visibility: deep multi-alt lockout, vault, and currency scans are skipped completely while the Alts panel is hidden.

### Vehicle UI & Module Polish
- **Streamlined Vehicle Bar (`frames/bars/vehicle.lua`)**:
  - Modernized vehicle detection, power tracking, and action bar transition logic.
