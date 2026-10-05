# Changelog

## v12.1.0-71 (2026-10-05)

### Features & Major Improvements

- **Auto-Gear BoE Confirmation Window Handling (`frames/gear/highest.lua`)**:
  - **Unbound BoE Equip Support**: Detected unbound Bind on Equip (BoE) items prior to pickup and equipped them directly via `EquipItemByName` to trigger the confirmation popup without cursor swapping collisions.
  - **Queue Watchdog Pause**: Suspended queue progression and paused the watchdog while `StaticPopupDialogs["EQUIP_BIND"]` (or tradeable/refundable popups) is active, cleanly resuming the equip queue once accepted or cancelled.

- **Quest Tracker Camelot Warband Completed Tooltips (`frames/quests/`)**:
  - **Account Completion Visibility**: Enabled "warband completed" tags in quest block tooltips on Camelot and Classic by querying `C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID)` in `frames/quests/modules/q_camelot.lua` and `frames/quests/modules/q_camelot_class.lua`.
  - **Universal Fallback**: Removed legacy `and not isCamelot` filter in `frames/quests/helpers/q_tooltip.lua` and added a direct fallback check on `questID` to guarantee account completion displays reliably across all quest modules with strict lowercase styling.

- **Theme Bar Style Castbar Replica Default (`frames/themes/`, `config.lua`, `commands.lua`, `frames/options/tabs/tab_bars.lua`)**:
  - **Castbar Replica Default**: Updated default theme bar style from `"inset"` to `"castbar"` (`"castbar replica (1:1 black)"`) across `config.lua`, `frames/themes/camelot.lua`, `frames/themes/engine.lua`, `commands.lua`, and `frames/options/tabs/tab_bars.lua`.
  - **Clean Framing**: Status bars default out of the box to the pure pitch-black border with no decor overlays.

- **Tracking Manager Center Bar Default Settings (`frames/tracking/`, `config.lua`)**:
  - **Updated Default Profile**: Configured default settings for the center tracking bar (`center_panel`, `CENTER`, and Druid/Rogue forms) to:
    - **Hide Out of Combat** (`hideOOC = true`)
    - **Hide in Vehicle UI** (`hideInVehicle = true`)
    - **Hide While Mounted** (`hideMounted = true`)
    - **Span Width** (`spanWidth = true`)
  - **Engine & Options Sync**: Updated `config.lua`, `frames/tracking/panels.lua` (including a migration for existing saved panels), `frames/tracking/trackedicons.lua`, and `frames/tracking/trackedoptions.lua` to ensure consistent fallback resolution and checkbox states.

- **Tracked Bar Default Position & Anchor Restoration (`frames/tracking/`, `common.lua`, `frames/bars/swing.lua`)**:
  - **Tracked Bars Position Restoration**: Fixed an issue where opening the tracking options initialized `db.anchor` to `{ x = 0, y = 0 }`, causing `sfui.trackedbars.UpdatePosition()` to dock the tracked bars container at the bottom edge of the screen (`SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)`) instead of the default `x = -300, y = 300`.
  - **Automatic SavedVariables Healing**: Added self-healing logic in `common.lua`, `frames/tracking/trackedbars.lua`, and `frames/tracking/trackedoptions.lua` that automatically recovers corrupted `{ x = 0, y = 0 }` coordinates back to `{ x = -300, y = 300 }`.
  - **Center Panel Anchor Validation**: Added point validation in `frames/tracking/trackedicons.lua` and `frames/bars/swing.lua` so that when panels anchor below swing bars or health bars, they verify that the target frame has valid points (`GetNumPoints() > 0`) before anchoring, preventing center panels from ever collapsing to the bottom edge of the screen when swing bars or health bars are initializing.
  - **Auto-Span Width Bound Guard**: Guarded `ApplyAutoSpan` so that if `targetFrame` defaults to `UIParent`, target width respects the configured health bar width instead of stretching across the entire monitor display width.

- **Merchant Window Subsystem Organization & Strata Elevation (`frames/merchant/`)**:
  - **File Reorganization**: Moved `frames/merchant.lua` into its own dedicated directory at `frames/merchant/merchant.lua`, updating `sfui.toc` and `dispatcher.lua` accordingly.
  - **Elevated to High Strata**: Set `SfuiMerchantFrame` frame strata to `"HIGH"` and enabled `SetToplevel(true)` so the merchant grid window renders cleanly above tracked bars, swing bars, and other medium-strata hud elements when open.

- **Classic Swing Timer Dynamic Attack Visibility (`frames/bars/swing.lua`)**:
  - **Attack-State Driven Visibility**: Updated melee swing bars (main-hand and off-hand) to mirror the dynamic behavior of ranged swing bars, remaining completely hidden unless actively attacking or mid-swing.
  - **Combat Event Integration**: Wired `PLAYER_ENTER_COMBAT` and `PLAYER_LEAVE_COMBAT` (alongside `IsCurrentSpell(6603)` fallback and `PLAYER_DEAD` cleanup) to govern melee auto-attack state, eliminating static empty swing bars when merely in combat or targeting enemies without attacking.
  - **Clean Exits & Stable Anchoring**: Allowed active swing animations to finish before fading out on combat disengagement, while maintaining stable anchor references in `GetLowestPossibleBar()` so HUD modules like the center tracking bar stay firmly positioned.
