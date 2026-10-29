# changelog

## v1.125 (2026-10-29)

### features

- **dispatcher & timer error diagnostics (`dispatcher.lua`, `frames/options/tabs/tab_debug.lua`, `scripts/bugjar-autofix.py`)**:
  - replaced stripped `pcall` dispatch in `dispatcher.lua` with `xpcall` using a full `debugstack(2, 12, 12)` capture, preserving inner stack frames across event handlers, one-shot timers (`sfui.events.After`), and tickers (`sfui.events.NewTicker`).
  - recorded handler registration call-site (`source`) at registration time and appended `[handler: ...]` and `[event: ... | args: ...]` context tags (with `issecretvalue` protection for secret arguments) to forwarded `!BugJar` errors.
  - updated the debug options tab (`frames/options/tabs/tab_debug.lua`) and `scripts/bugjar-autofix.py` to display and parse the enriched multi-frame dispatcher stack traces.

- **taint-free special frame escape registry (`common.lua`, `frames/actionbars/bind.lua`, `frames/actionbars/movers.lua`, `frames/alts/alts.lua`, `frames/alts/mail_ui.lua`, `frames/dungeonjournal/dungeonjournal.lua`, `frames/fishing/fishing_atlas.lua`, `frames/gear/lootviewer.lua`, `frames/mem.lua`, `frames/merchant/merchant.lua`, `frames/options/options.lua`, `frames/portals/portals.lua`, `frames/professions/browser.lua`, `frames/tracking/trackedoptions.lua`)**:
  - added `sfui.common.register_special_frame` in `common.lua` using a private `ESCAPE` override binding and `PLAYER_REGEN_DISABLED` auto-clear instead of inserting addon frame names into `_G.UISpecialFrames`.
  - migrated all 15 addon windows off `_G.UISpecialFrames` so `CloseSpecialWindows()` is never tainted when opening `GameMenuFrame` or `EditModeManagerFrame`.

### improvements & bug fixes

- **blizzard edit mode taint elimination (`frames/themes/nineslice_themes.lua`, `frames/themes/engine.lua`, `frames/hide.lua`, `frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`, `frames/quests/engine/q_tracker.lua`, `frames/bars/bars.lua`, `frames/bars/target.lua`, `frames/bars/castbar.lua`, `frames/experience/events.lua`, `frames/map/minimap.lua`)**:
  - stopped writing fallback layouts to `_G.NineSliceLayouts` in `frames/themes/nineslice_themes.lua` and moved them to `sfui.theme.customNineSliceLayouts` (read by `sfui.theme.GetNineSliceLayout` in `frames/themes/engine.lua`), fixing `NineSliceUtil.GetLayout()` taint during `StanceBar:HighlightSystem()` in `EditModeFrameSetup()` that caused `[Forbidden] sfui tried to call the protected function 'ClearTarget()'` and secret color value comparison errors in `CompactUnitFrame.lua`.
  - removed direct table mutations (`.defaultHideSelection`, `.Selection:Hide()`), `SetPoint` hooks, and `EditModeManagerFrame` method hooks across `frames/hide.lua`, `frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`, `frames/quests/engine/q_tracker.lua`, `frames/bars/bars.lua`, `frames/bars/target.lua`, `frames/bars/castbar.lua`, `frames/experience/events.lua`, and `frames/map/minimap.lua`.
  - replaced `EventRegistry` callbacks on `EditMode.Enter` / `EditMode.Exit` with a clean post-hook on `FormattingUtil.GetMinimumWidth` (called exclusively by `EditModeManagerFrame:UpdateDropdownOptions` and `OnEditModeExit`).

- **global namespace hygiene (`compat.lua`, `core/widgets.lua`, `frames/automation/automation.lua`, `frames/merchant/merchant_utility.lua`)**:
  - localized stray globals (`activeTextureMenu`, `prevDisplay`, `_lfg_dialog_show_hooked`, `WOW_PROJECT_CAMELOT`) and guarded `AuraUtil.FindAuraByName` fallback with `not IS_RETAIL` so `_G` is never polluted on retail.
