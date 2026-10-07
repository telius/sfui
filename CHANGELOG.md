# Changelog

## v12.1.0-79 (2026-10-07)

### features & enhancements

- **stealth tracking bucket for rogues**: added rogue stealth assignment bucket alongside druid stealth bucket in `frames/tracking/cdm.lua` so rogue stealth abilities can be assigned and tracked cleanly.
- **combo point bar height offset**: added a configurable combo point height offset setting in `config.lua` (`comboPointHeightOffset = -4`) and applied it in `frames/bars/bars.lua` to reduce rogue and druid combo point bars by 4px.
- **error frame filtering**: added "not enough energy" (`LE_GAME_ERR_OUT_OF_ENERGY`) suppression to the ui errors frame filtering in `frames/hide.lua` and `frames/options/tabs/tab_hide.lua`.

### bug fixes & improvements

- **swing timer combat stat secrecy**: fixed a runtime crash in `frames/bars/swing.lua` where evaluating `rangedSpeed > 0` and `offHandSpeed > 0` directly on secret numbers returned by `UnitAttackSpeed("player")` threw a secret value comparison error when popping haste buffs like "berserking" in combat.
  - added safe `IsAttackSpeedValid` validation in `core/safety.lua` and `frames/bars/swing.lua`.
  - guarded `sfui.safety.IsNumericAndPositive` against secret values.
  - safeguarded swing timer duration, end times, and debug telemetry from secret arithmetic and comparisons.
- **combat state tracking**: centralized combat state tracking in `common.lua` (`sfui.common.is_in_combat(event)`, `sfui.in_combat`), avoiding polling slow or restricted c-apis on hot execution paths.
- **tracked icons and bars out-of-combat visibility**: resolved an issue on low-level characters in camelot / classic era where tracked icon panels and bars failed to reliably appear upon entering combat when "hide out of combat" was enabled.
- **tracked icons fast-track optimization**: streamlined the `UpdateAllIconStates` loop in `frames/tracking/trackedicons.lua` to only iterate active shown panels and reuse cached panel configurations.
