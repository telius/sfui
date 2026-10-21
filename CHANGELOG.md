# changelog

## v1.116 (2026-10-21)

### improvements & bug fixes

- **cdm item cooldown support & countdown timers (trinkets, healthstone, combat potion, health potion)**:
  - assignments pool: expanded pool queries to include blizzard cdm category 7 (`EquipSlotEssential`) and category 5 (`SpecAgnosticEssential`), allowing on-use trinkets, combat potions, health potions, and healthstones to appear in the pool and be assigned to panels (`frames/tracking/cdm.lua`).
  - metadata & texture resolution: added `SPELL_CATEGORY_METADATA` and `ResolveCooldownMetadata` to resolve icon textures, names, and slot details for trinkets and category items. aligned category textures with blizzard's authoritative `Interface/ICONS/INV_POTION_114` and `Interface/ICONS/INV_POTION_54` paths so potion icons match blizzard's cdm (`frames/tracking/cdm.lua`, `frames/tracking/panels.lua`, `frames/tracking/trackedicons.lua`).
  - live cooldown tracking & countdown numbers: updated `update_item_cd` to generate a `LuaDurationObject` via `C_DurationUtil` and apply `SetCooldownFromDurationObject`, restoring active cooldown swipes and numerical countdown text on items dragged from inventory and assigned cdm items (`frames/tracking/trackedicons.lua`).
  - combat item cooldown restoration: removed the combat suppression check in `compat.lua` that zeroed item cooldowns mid-combat. potion / healthstone category cooldowns forward the category source straight into `C_Spell.GetSpellCooldownDuration` → `SetCooldownFromDurationObject`, reading only never-secret `isActive` / `isEnabled` flags without inspecting secrets (`compat.lua`, `frames/tracking/trackedicons.lua`).
  - inventory drops: automatically mapped dragged trinkets to equipment slots 13/14 and healthstones to their respective categories, and ensured all added items default to enabled countdown text (`frames/tracking/cdm.lua`).
  - panel filtering: prevented active item cooldowns from being discarded by spellbook checks when unlearned in spellbook (`frames/tracking/panels.lua`).
  - flat icon outline removal: eliminated the 2px inset gap and black `borderBackdrop` outline from `apply_square_icon_style` while preserving clean flat 8% cropped icons across tracked bars, castbars, vehicle buttons, and minimap buttons (`core/widgets.lua`, `config.lua`, `frames/tracking/trackedbars.lua`, `frames/bars/vehicle.lua`, `frames/map/buttons.lua`).
  - tracked bars combat protected error: removed redundant `bar.status:Show()` calls from `SetupBarState` that triggered `[Blocked] sfui tried to call the protected function 'StatusBar:Show()'` during combat layout updates, and guarded `:SetParent` calls (`frames/tracking/trackedbars.lua`).

- **midnight 12.1.5 item upgrade tracking & decommissioned currency cleanup**:
  - ascendant venomstone tracking: added ascendant venomstone (`280562`) to the seasonal currencies list for bag and bank tracking (`data/season.lua`).
  - decommissioned voidcore cleanup: retired nebulous voidcore (`3418`), ascendant voidcore (`268552`), and voidlight marl (`3316`), purging legacy records and cap data from saved variables (`data/season.lua`, `frames/alts/alts_standard.lua`).
  - alt overview currency rendering: updated alt currency cell rendering and synchronization with dynamic item icon resolution, safe texture escape formatting, and automatic refresh on item info cache loads via `GET_ITEM_INFO_RECEIVED` (`frames/alts/alts_standard.lua`).
