# Changelog

## v12.1.0-80 (2026-10-07)

### features & enhancements

- **canonical library packaging**: updated `.pkgmeta` and `scripts/update-libs.sh` to pull `CallbackHandler-1.0` (minor 8) and `LibDBIcon-1.0` (minor 56) directly from canonical CurseForge SVN repositories rather than outdated git mirrors.
- **shield stat evaluation**: added block value and block chance parsing to `core/items.lua` via `sfui.items.get_shield_stats`, ensuring shields with higher block value properly outscore lower block alternatives in `frames/gear/highest.lua`.
- **rogue weapon weighting**: refined weapon evaluation in `frames/gear/highest.lua` for rogues to prioritize daggers for Backstab, slow high-damage main-hand weapons, and dual wield capability verification (level 10+ passive trainer skill on Camelot/Classic via `core/talents.lua` and `core/talents_camelot.lua`).

### bug fixes & improvements

- **minimap icon login crash**: resolved `core.lua:406: attempt to call a nil value` on login caused by an ancient `CallbackHandler-1.0` mirror invoking deprecated `table.getn` during `LibDBIcon-1.0` initialization.
- **defensive broker registration**: guarded minimap icon registration in `core.lua` to check for callable `icon.Register`, reuse existing broker objects from `LibDataBroker-1.1`, and verify `not icon:IsRegistered("sfui")` before registering.
