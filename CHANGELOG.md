# changelog

## v1.117 (2026-10-22)

### improvements & bug fixes

- **pet combat protected actionbar clearallpoints taint fix**:
  - prevented blizzard editmode action bar updates from calling protected `MainActionBar:ClearAllPointsBase()` during combat with a pet out (`frames/actionbars/actionbars.lua`).
  - neutralized `Show`, `ShowOverride`, and `UpdateVisibility` cascades on suppressed `PetActionBar`, `PetActionBarFrame`, and `MainActionBar` so ambient pet state and vehicle leave button triggers do not invoke editmode layout recalculations (`frames/actionbars/actionbars.lua`).
  - unverified/tainted events fully purged by unregistering events across all suppressed bars and returning `false` for `IsInDefaultPosition()`, and added `InCombatLockdown()` early-outs to `UpdateBottomActionBarPositions`, `UpdateRightActionBarPositions`, and `UpdateActionBarLayout` on `EditModeManagerFrame` (`frames/actionbars/actionbars.lua`).

- **alts overview nebulous voidcore tracking restoration**:
  - restored nebulous voidcore (`3418`) to `sfui.season.CURRENCIES` for active tracking and removed it from the weekly reset currency purge table (`data/season.lua`, `frames/alts/alts_standard.lua`).

- **text status bar protected show taint fix**:
  - removed redundant `self:Show()` invocation from `forward_statusbar_values` on status bars inheriting `SecureFrameParentPropagationTemplate`, preventing combat action blocked errors during text status bar value updates (`core/safety.lua`).
