# changelog

## v1.146 (2026-11-11)

### new features & improvements

- **tracking & reminders modular architecture (`frames/tracking/entry.lua`, `frames/tracking/auras.lua`, `frames/tracking/tracking_camelot.lua`, `frames/tracking/icon_aura.lua`, `frames/tracking/icon_cooldown.lua`, `frames/tracking/trackedicons.lua`, `frames/reminders/buffs_providers.lua`, `frames/reminders/buffs.lua`, `sfui.toc`)**:
  - decomposed cooldown and aura tracking into dedicated descriptor, aura-resolution, revision-gated icon aura, and cooldown/charge/glow modules, plus isolated forever multi-rank spell and paladin seal resolution in `frames/tracking/tracking_camelot.lua`.
  - modularized buff reminder providers (`frames/reminders/buffs_providers.lua`), added paladin party blessing reminders (`frames/reminders/buffs_party.lua`, `frames/options/tabs/tab_buffs.lua`), and expanded consumable reminder coverage (`frames/reminders/buffs_consumables.lua`, `frames/reminders/buffs_data.lua`).
- **tracked buffs socket & options tab on retail and camelot (`frames/tracking/buffs.lua`, `frames/tracking/trackedoptions.lua`, `sfui.toc`)**:
  - restored `SfuiTrackedBuffsSocket` and wired the `buffs` tab in `frames/tracking/trackedoptions.lua` to read assigned cooldown manager buffs via `CooldownViewerSettings`, `C_CooldownViewer`, and live `BuffIconCooldownViewer` items without tainting `CheckBuildDisplayData`.
  - enabled the tracked buffs socket and options configuration across both retail (`standard`) and forever (`camelot`).
- **universal mover support for all tracked panels (`frames/actionbars/movers.lua`, `frames/tracking/trackedicons.lua`, `frames/tracking/trackedoptions.lua`, `frames/tracking/trackedbars.lua`, `frames/tracking/buffs.lua`, `frames/bars/bars.lua`)**:
  - registered all tracked icon panels (`CENTER`, `UTILITY`, `Left`, `Right`, druid/rogue/warrior form & stance panels, and custom panels), tracked bars, and tracked buffs with `sfui.movers`, including form-sibling synchronization, dependent panel re-anchoring, empty-panel edit-mode sizing, and position resets.

### bug fixes & cpu optimizations

- **tracked bars shifting numbers & secret-value safety (`frames/tracking/trackedbars.lua`, `frames/tracking/tracking_classic.lua`, `config.lua`)**:
  - switched numeric bar timers and stack readouts from proportional `GameFontNormalSmall` to tabular `NumberFontNormalSmall` with explicit horizontal justification, bounded label anchors, consistent font sizing across pooled bars, and integer-rounded bar widths.
  - eliminated 50ms `"1"` <-> `"0"` stack oscillation and timer/stack text ping-pong on `showStacksText` duration bars (such as ignore pain), gated spell-name writes behind `not isTimerAndStacks`, removed `PandemicIcon` reparenting taint, and replaced `pcall` probing with direct untainted widget forwarding.
- **tracking hot-path cpu, taint & glow optimizations (`frames/tracking/buffs.lua`, `frames/tracking/glows.lua`, `frames/tracking/auras.lua`, `frames/tracking/entry.lua`, `frames/tracking/icon_aura.lua`, `frames/tracking/icon_cooldown.lua`, `frames/tracking/panels.lua`, `frames/tracking/cdm.lua`, `frames/tracking/trackedicons.lua`)**:
  - removed per-frame `ShowPandemicStateFrame` / `HidePandemicStateFrame` post-hooks and custom fields on `BuffIconCooldownViewer` items in `frames/tracking/buffs.lua`, replacing them with weak-keyed state tables, coalesced syncs, and an idle-gated 10hz pandemic check while preserving untainted m+ secret-cooldown swipes.
  - eliminated per-call `string.format` / `table.concat` signature churn and temporary table allocations in `frames/tracking/glows.lua`, added `_glowConfigRev` fast-path skipping and multi-charge partial recovery edge indicators in `frames/tracking/icon_cooldown.lua`, stopped active glows whenever panels hide, and gated cdm drag `OnUpdate` scripts so they only run during active drags.
  - refreshed camelot dungeon journal drop rates, quest rewards, and profession recipe datasets (`data/dj_camelot.lua`, `data/recipes_camelot.lua`).
