# Changelog

## v12.1.0-78 (2026-10-07)

### bug fixes & improvements

- **blizzard cooldown viewer suppression**: resolved an issue on classic forever / camelot where blizzard's default "essential cooldowns" bar would reappear when logging in or shapeshifting in bear form.
  - disarmed blizzard's `BottomManagedFrameContainer` in `common.lua` by clearing `hideWhenActionBarIsOverriden`, setting `ignoreFramePositionManager`, and detaching managed frames out-of-combat to prevent action bar transitions from stomping alpha.
  - installed a recursion-safe `SetAlpha` and `EnableMouse` hook on `EssentialCooldownViewer`, `UtilityCooldownViewer`, and `BuffBarCooldownViewer` to enforce invisibility even if edit mode or layout systems attempt to restore full opacity.
  - unified event-driven suppression across retail and camelot/classic in `common.lua`, ensuring `EDIT_MODE_LAYOUTS_UPDATED`, `UPDATE_SHAPESHIFT_FORM`, and `UPDATE_BONUS_ACTIONBAR` are reliably handled with full combat lockdown protection.
