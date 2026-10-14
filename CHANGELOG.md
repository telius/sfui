# Changelog

## v2.00 (2026-10-14)

### features

- **pandemic tracking & bar recolor**: implemented secret-safe pandemic detection via blizzard's native `ShowPandemicStateFrame` and `HidePandemicStateFrame` hooks (`frames/tracking/trackedbars.lua`), smoothly transitioning bar status color into customizable pandemic color (`config.lua`, `frames/tracking/trackedoptions.lua`) without intrusive bar markers.
- **native pixel layout rounding**: integrated retail 12.1.5 `SetRoundLayoutToNearestPixel` and `PixelUtil.SetRoundLayoutToNearestPixelRecursively` across core widgets (`core/widgets.lua`), theme engine (`frames/themes/engine.lua`), and action bars (`frames/actionbars/bars.lua`) for razor-sharp borders and zero sub-pixel blurring.
- **real-time ambient weather widget**: added live weather indicator frame with mouseover tooltip showing weather name and intensity percentage beside the minimap clock (`frames/automation/minimap.lua`, `frames/options/tabs/tab_minimap.lua`).

### improvements & bug fixes

- **vehicle keybinds & actionbar paging**: fixed vehicle and override bar paging conditions in `frames/actionbars/paging.lua` (`[overridebar] override`, `[vehicleui] possess`, `[possessbar] possess`), expanded `_onstate-page` to resolve dynamic indices via `GetVehicleBarIndex()`, and expanded bar 1 state mapping across 18 action pages (`frames/actionbars/bars.lua`).
- **vehicle bar priority overrides**: added priority override keybindings to `frames/bars/vehicle.lua` ensuring vehicle buttons 1–6 intercept hardware keys directly when the vehicle bar is shown.
- **zero-taint secret-safe architecture**: eliminated calls to restricted `GetRefreshCarryOverDuration`, removed status bar texture layout coordinate comparisons (`curTex:GetRight()`), and eliminated secure mixin monkeypatching (`frames/tracking/trackedbars.lua`), fully preventing secret number comparison errors and lua taint exceptions during combat and mythic+.
- **tracked bar recycling & config cache**: restored stack limits cleanup in `RecycleBar` and added `GetBarNormalColor` helper for seamless color restoration upon exiting pandemic windows.
