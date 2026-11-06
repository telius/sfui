# changelog

## v1.141 (2026-11-06)

### bug fixes

- **blizzard unitframe & textstatusbar taint isolation (`core/safety.lua`, `frames/bars/bars.lua`, `frames/hide.lua`)**:
  - removed legacy `TextStatusBarMixin` and `PlayerFrame` status bar method overrides (`forward_statusbar_values` / `protect_core_status_bars`) in `core/safety.lua` that tainted `PlayerFrame.ManaBar.forceUpdate` and `currValue` during `UNIT_MAXPOWER` updates (such as equipping a fishing pole), resolving `UnitFrame.lua:918: attempt to compare local 'currValue' (a secret number value, while execution tainted by 'sfui')`.
  - removed unconditional `_G.PlayerFrame.Selection` mutation in `frames/bars/bars.lua` and gated `RestoreFrame` in `frames/hide.lua` so `sfui` never touches `PlayerFrame` or other unit frames unless explicitly suppressed by `sfui`.
