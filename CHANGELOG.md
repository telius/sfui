# Changelog

## v1.92 (2026-10-11)

### features

- **library book map pins**: added interactive world map pins for camelot / classic forever library book quests and faction librarians (`data/books_camelot.lua`, `frames/map/library_pins.lua`). includes all 40 book locations, zephras isle spawn nodes, milestone tracking (`friend of the library` and `greater friend of the library`), co-located pin clustering with count badges, and shift-click native map waypoints with super-tracking.
- **world map tracking dropdown integration**: integrated library book controls into `MENU_WORLD_MAP_TRACKING` with toggles for book pins, faction librarians, and hiding collected books by default.
- **warrior stance badge**: added a circular stance indicator centered on the top edge of the warrior healthbar in camelot (`frames/bars/bars.lua`) tracking battle, defensive, and berserker stances.
- **warrior stance center bar**: added dedicated center bar stance tracking for warriors in camelot (`frames/tracking/cdm.lua`, `frames/tracking/trackedicons.lua`, `frames/tracking/panels.lua`).
- **merchant silver & copper display**: enhanced merchant currency rendering in camelot / classic to display silver and copper denominations alongside gold (`frames/merchant/merchant.lua`, `frames/merchant/merchant_filter.lua`, `frames/merchant/merchant_utility.lua`).

### improvements & bug fixes

- **dungeon journal level filter**: fixed the level range filter clamping in camelot dungeon journal (`frames/dungeonjournal/dungeonjournal.lua`, `frames/dungeonjournal/dj_sidebar.lua`, `frames/dungeonjournal/dj_pins.lua`) to correctly evaluate min/max level bounds for the active character.
- **alts recipe matrix error**: resolved an indexed string assignment error on `filterState` in `frames/alts/recipes.lua`.
- **experience & reputation options**: expanded reputation and experience tracking configuration in `frames/experience/*` and `frames/options/tabs/tab_experience.lua`.
