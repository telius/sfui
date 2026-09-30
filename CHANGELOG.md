# Changelog

## v12.1.0-63 (2026-09-30)

### Fixes & Major Improvements
- **CI & Static Analysis (.luacheckrc)**:
  - Configured comprehensive WoW environment rules in `.luacheckrc` to eliminate false-positive global/whitespace warnings and ensure 100% clean CI validation (0 warnings, 0 errors).
  - Fixed variable shadowing in `frames/gear/gear.lua`.

- **Diagnostics & Memory Profiler (`frames/mem.lua`, `frames/automation.lua`)**:
  - Cleaned up automation diagnostics card by removing unused `auto-fill` and `skip cine` placeholders.
  - Replaced entries with active status indicators for `auto-repair` and `sell-greys`.

- **LFG Automation & Role Confirmation (`frames/automation.lua`)**:
  - Automatically applies Dungeon Finder roles and skips the "Choose your Roles" popup on `LFGListApplicationDialog`.
  - Dynamically synchronizes role checkbuttons from `LFDQueueFrame_GetRoles()` and `GetLFGRoles()` with active specialization fallback.
  - Resolved module lifecycle registration issue where `sfui.RegisterModule("automation")` lacked `OnInit`/`OnEnable` callbacks.
