# Changelog

## v12.1.0-56 (2026-09-26)

### Tracking Bars & Blizzard CooldownViewer Overhaul
- **Zero-Taint CooldownViewer Architecture (`common.lua`, `frames/tracking/trackedbars.lua`, `frames/tracking/trackedicons.lua`)**:
  - Eliminated all invasive `HookScript("OnShow")`, secure method hooks (`SetAlpha`, `UpdateSystemSetting*`), and table mutations on Blizzard's `BuffBarCooldownViewer`, `EssentialCooldownViewer`, and `UtilityCooldownViewer`.
  - Fixed fatal `attempted to index a table that cannot be accessed while tainted` crash in Blizzard's internal `auraInstanceIDToItemFramesMap` proxy table upon buff application (e.g. Anti-Magic Shell).
  - Cleaned viewer hiding to be strictly passive via `viewer:SetAlpha(0)` and `viewer:EnableMouse(false)`.

### Secret Value Safety & Combat Crash Immunity
- **Robust Guarding for Secret Numbers & Bools (`frames/tracking/trackedbars.lua`)**:
  - Eliminated arithmetic and comparison crashes on secret values in combat (`attempt to compare a secret number value, while execution tainted by 'sfui'`).
  - Prioritized static, non-secret database IDs (`config.spellID`, `info.spellID`) from `C_CooldownViewer` over live dynamic obfuscated aura handles.
  - Added strict `issecretvalue()` guards to all fallback spell ID lookups, charge queries, and visibility predicates.

### Performance & Pacing Optimization
- **Relaxed Out-of-Combat Update Loop (`frames/tracking/trackedbars.lua`)**:
  - Paced periodic structural checks out of combat to 1.0s (active bars) and 2.0s (idle with 0 bars), drastically reducing idle CPU overhead.
  - Added 1.0s debounce pacing on non-combat event bursts (`UNIT_AURA`, `SPELL_UPDATE_COOLDOWN`, `BAG_UPDATE_COOLDOWN`) while preserving instant 0-delay reaction for first-time ability activations.
  - Retained real-time 0.05s status bar progression and 0.5s in-combat polling for smooth, responsive animations during encounters.

### Modernization & Legacy Cleanup
- **Retail & Camelot Focus (`compat.lua`, `core/safety.lua`, `dispatcher.lua`, `frames/quests/`)**:
  - Cleaned redundant classic fallbacks and pcall wrappers across core modules.
