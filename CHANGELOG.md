# Changelog

## v1.86 (2026-10-08)

### features

- **auto-switch to gained reputation**: added an opt-in toggle in `frames/options/tabs/tab_experience.lua` (default off) that automatically activates the reputation bar and swaps the watched faction whenever reputation is gained.
- **spillover reputation batching**: implemented a debounced multi-faction batch aggregator in `frames/experience/events.lua` that resolves simultaneous spillover reputation gains (e.g. Horde/Alliance faction turn-ins) by selecting the primary quest faction with the highest gain rather than an arbitrary spillover recipient.
- **cross-client reputation switching**: unified modern `C_Reputation` / `C_MajorFactions` and classic `GetFactionInfo` / `SetWatchedFactionIndex` in `frames/experience/data.lua` with O(1) cached lookup and redundant-switch prevention.

### improvements & bug fixes

- **totem frame secret value taint fix**: resolved fatal crash `attempt to perform numeric conversion on a secret number value (execution tainted by 'sfui')` in `TotemFrame.lua` on WoW 12.1.0 (Midnight / Retail).
- **unit frame taint elimination**: in `frames/hide.lua`, removed direct `frame:Update()` calls, eliminated `totemPool` button state mutation, stopped attaching custom fields directly to Blizzard frame tables, and restricted `TotemFrame` hiding on Retail strictly to visual opacity without touching secure layouts.
