# changelog

## v1.107 (2026-10-17)

### improvements & bug fixes

- **combat telemetry equipped weapon skill tracking**: main-hand, off-hand, and ranged skill rows now dynamically follow the equipped weapon's skill category (e.g. swords, daggers, bows) and effective skill including racials and gear bonuses. druid shapeshift forms map to feral combat (skill 3014) and unarmed fallback (skill 162) (`frames/character/infopanel.lua`, `frames/gear/gear_camelot.lua`).
- **camelot gear system skill extraction**: weapon detection, subclass mapping, and skill calculation are integrated directly into `sfui.gear.get_equipped_weapon_info` in `frames/gear/gear_camelot.lua` with zero-allocation caching, eliminating redundant item parsing in `infopanel.lua`.
- **camelot guard & shapeshift reactivity**: strictly guarded `frames/character/infopanel.lua` to camelot only (`if not sfui.isCamelot then return end`) and added `UPDATE_SHAPESHIFT_FORM` to the telemetry event watcher for real-time form updates (`frames/character/infopanel.lua`).
- **mouse cursor ring fix & sizing**: restored the mouse cursor ring frame lifecycle and visibility tracking, guaranteed initialization on login, and reduced the ring diameter to 75% (48px) for optimal mouse targeting clarity (`frames/cursor.lua`, `core.lua`).
- **challenge bar disabled by default**: set `trackLegacy = false` and disabled the challenge progress bar by default across experience frames and settings (`config.lua`, `frames/experience/challenges.lua`, `frames/experience/experience.lua`, `frames/experience/reputation.lua`, `frames/options/tabs/tab_experience.lua`).
