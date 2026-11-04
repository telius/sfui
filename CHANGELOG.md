# changelog

## v1.136 (2026-11-05)

### bug fixes

- **forever blizzard swing timer suppression (`frames/bars/swing.lua`)**:
  - fixed an issue in wow forever where blizzard's `EditModeSwingTimerSystemMixin:UpdateSystemSettingOpacity()` restored the default `SwingTimerMainHandFrame` alpha on `EDIT_MODE_LAYOUTS_UPDATED` after the initial load-time suppression.
  - removed the one-shot `blizzardSuppressed` early-return latch, unregistered all events on `SwingTimerManagerFrame` (with post-hooks on `UpdateSharedEventRegistration` and `UpdateSwingEventRegistration`), and added taint-free `SetAlpha` and `OnShow` post-hooks across `SwingTimerMainHandFrame`, `SwingTimerOffHandFrame`, and `SwingTimerRangedFrame`.
