# Changelog

## v12.1.0-57 (2026-09-26)

### Features
- **In-Menu Fishing Keybind Interface (`frames/options/tabs/tab_fishing.lua`, `frames/fishing.lua`)**:
  - Added an interactive keybinding button (`[ bind key ]` / `[ rebind key ]`) directly inside the Fishing options tab.
  - Full support for multi-modifier key chords (`Shift`, `Ctrl`, `Alt`, `Meta`), extra mouse buttons (`Button3`–`Button8`), mouse wheel scrolling (`MOUSEWHEELUP` / `MOUSEWHEELDOWN`), and gamepad buttons/triggers.
  - Added single-click `[ unbind ]` button and right-click shortcut on the bind button to quickly clear fishing keybinds.
  - Safe modal capture overlay with `ESC` / click-to-cancel support, plus automatic cancellation on combat entry (`PLAYER_REGEN_DISABLED`) or menu close.
  - Implemented core lifecycle APIs: `sfui.fishing.set_keybind()` and `sfui.fishing.unbind_keybinds()`.

### Companion Pet Management
- **Pet Dismissal Support (`frames/pets.lua`, `commands.lua`)**:
  - Added `sfui.pets.Dismiss()` and `/sfpet dismiss` command to easily dismiss the active summoned companion pet.
  - Refined character favorites pooling and summoning routines.

### UI & Core Architecture
- **Standardized Widget Factory (`core/widgets.lua`, `core/safety.lua`)**:
  - Centralized widget builder methods for custom inputs, checkboxes, sliders, and flat buttons.
  - Cleaned up legacy safety wrappers in favor of modern client standards.

### Tracking Bars & Stability Refinements
- **Protected Values & Secret Safety (`frames/tracking/trackedbars.lua`)**:
  - Hardened status bar value synchronization (`status:SetValue`) against secret numbers and protected proxy values during combat.
  - Improved stack count caching and string coercion checks.
