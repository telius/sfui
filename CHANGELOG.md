# Changelog

## v12.1.0-62 (2026-09-30)

### Fixes & Major Improvements
- **LFG Automation & Role Confirmation (`frames/automation.lua`)**:
  - Fixed Premade Groups sign-up dialog (`LFGListApplicationDialog`) so it automatically applies Dungeon Finder roles and skips the "Choose your Roles" popup.
  - Dynamically synchronizes role checkbuttons from `LFDQueueFrame_GetRoles()` and `GetLFGRoles()` with active specialization fallback.
  - Resolved module lifecycle registration issue where `sfui.RegisterModule("automation")` lacked `OnInit`/`OnEnable` callbacks, ensuring reliable hook attachment on load, login, and PVE frame presentation.
  - Ensured reliable double-click signups in LFG search results and role checks via `CompleteLFGRoleCheck`.

- **Architecture & Performance Refinements**:
  - Reorganized gear manager, stat provider, and tracking bar helpers into dedicated modular components (`core/bridge.lua`, `data/stats.lua`, `frames/tracking/panels.lua`).
  - Cleaned up legacy engine files and updated library dependencies.
