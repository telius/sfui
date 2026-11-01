# changelog

## v1.129 (2026-11-01)

### features & improvements

- **camelot synced skill tracking & `spec_color` bars (`frames/quests/modules/q_camelot_skills.lua`, `frames/quests/engine/q_layout.lua`, `frames/sync/multibox.lua`, `frames/sync/sync.lua`)**:
  - tracked skill progress bars in the camelot objective tracker now inherit `spec_color` (`sfui.common.get_class_or_spec_color()`), updating automatically on `SFUI_SPEC_CHANGED` and `SFUI_SPEC_COLORS_UPDATED`.
  - added live cross-client tracked skills synchronization (`DELTA_TRACKED_SKILLS` and `DELTA_SKILL_UNTRACK`) so tracked skills from synced peers are displayed on both clients in their character's `spec_color`, with multi-bar stacking (`bData.progressBars`), per-character rank tooltips, and remote untrack support via shift-click or right-click.
- **sync party hud unit tokens on mouseover (`frames/sync/hud.lua`)**:
  - added client-assigned unit tokens (`(player)`, `(party1)`, `(party2)`, etc.) to the per-character mouseover tooltip and footer summary tooltip on the sync party hud.
- **fishing background sound management (`frames/automation/fishing.lua`)**:
  - added dedicated `enable_bg_sound()` and `restore_bg_sound()` helpers so `Sound_EnableSoundWhenGameIsInBG` is always enabled while fishing (independent of `enhanceSounds`) and reliably restored to its previous user setting when done fishing, on logout, or on reload recovery.

### bug fixes

- **`SetHiddenGroupBuffs()` / `SetGroupBuffVisualAlerts()` taint fix (`common.lua`, `frames/actionbars/bind.lua`)**:
  - removed early `SetCVar("cooldownViewerEnabled", 1)` from `sfui.common.hide_blizzard_cooldown_viewers()` during `ADDON_LOADED` before `VARIABLES_LOADED`, preventing `CooldownViewerSettings:GetDataProvider().displayData` from being initialized in an addon-tainted execution context prior to `GroupBuffFilter`'s `CooldownViewerSettings.OnDataChanged` callback.
  - passed explicit `owner` arguments to `EventRegistry:RegisterCallback` calls in `common.lua` and `frames/actionbars/bind.lua` so `CallbackRegistry`'s internal `generateOwnerID` counter is never incremented from addon context.
