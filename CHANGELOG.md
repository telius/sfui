# Changelog

## v1.99 (2026-10-14)

### features

- **pandemic window & spark indicator**: added native pandemic glow and threshold spark on tracked bars (`frames/tracking/trackedbars.lua`, `config.lua`), automatically indicating the optimal carry-over refresh window.
- **native pixel layout rounding**: integrated retail 12.1.5 `SetRoundLayoutToNearestPixel` and `PixelUtil.SetRoundLayoutToNearestPixelRecursively` across core widgets (`core/widgets.lua`), theme engine (`frames/themes/engine.lua`), and action bars (`frames/actionbars/bars.lua`) for razor-sharp borders and zero sub-pixel blurring.
- **real-time ambient weather widget**: added live weather indicator frame with mouseover tooltip showing weather name and intensity percentage beside the minimap clock (`frames/automation/minimap.lua`, `frames/options/tabs/tab_minimap.lua`).

### improvements & bug fixes

- **vehicle keybinds & actionbar paging**: fixed vehicle and override bar paging conditions in `frames/actionbars/paging.lua` (`[overridebar] override`, `[vehicleui] possess`, `[possessbar] possess`), expanded `_onstate-page` to resolve dynamic indices via `GetVehicleBarIndex()`, and expanded bar 1 state mapping across 18 action pages (`frames/actionbars/bars.lua`).
- **vehicle bar priority overrides**: added priority override keybindings to `frames/bars/vehicle.lua` ensuring vehicle buttons 1–6 intercept hardware keys directly when the vehicle bar is shown.
- **pandemic secrecy & taint protection**: eliminated calls to restricted `GetRefreshCarryOverDuration` and avoided secret value comparisons on `pandemicStartTime`, `expirationTime`, and duration values (`frames/tracking/trackedbars.lua`), resolving errors at `CooldownViewer.lua:605` and `trackedbars.lua:1470`.
- **tracked bar recycling**: restored `bar._maxStacks = nil` cleanup in `RecycleBar` in `frames/tracking/trackedbars.lua`.
