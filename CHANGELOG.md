# changelog

## v1.106 (2026-10-17)

### improvements & bug fixes

- **naked gear stripping durability protection**: slot 18 is now excluded from unconditional unequip during naked mode. relics (totems, librams, idols, sigils) have no durability, take no death penalty, and have no visual model, so they remain safely equipped. ranged weapons with durability (bows, guns, crossbows, wands, thrown) continue to be unequipped dynamically for corpse runs (`frames/gear/gear_camelot.lua`).
- **shaman totem & paladin relic re-equipping**: fixed spec validation variable collision and added camelot spec id ranges (`14891..14893` for shamans, `14861..14863` for paladins) in `IsItemValidForSpec_Internal`, ensuring totems, librams, idols, and sigils are properly recognized, scored, and re-equipped into slot 18 (`frames/gear/highest.lua`).
- **dynamic relic slot labels & notifications**: slot 18 lock buttons and paperdoll shift-click notifications now dynamically label relics as "totem", "libram", "idol", or "sigil" instead of generic "rg"/"ranged" (`frames/gear/gear_camelot.lua`, `frames/gear/gear.lua`, `frames/gear/engine.lua`).
