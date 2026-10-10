# Changelog

## v1.88 (2026-10-10)

### features

- **inventory link resolution engine**: implemented `get_inventory_item_link` in `core/items.lua` with a five-tier fallback architecture (`_G.GetInventoryItemLink`, `C_TooltipInfo.GetInventoryItem`, `GetInventoryItemID`, private scanning tooltip `scanTip:SetInventoryItem`, and `ItemLocation`). seamlessly resolves equipment links across both modern and classic builds where native c functions return `nil` for slot 0.
- **camelot skill tracking api**: exported `sfui.camelot_skills` API and added `SFUI_SKILL_TRACKING_CHANGED` event messaging in `frames/quests/modules/q_camelot_skills.lua` for tracking and toggling skill objectives.

### improvements & bug fixes

- **ammo slot auto-equip loop fix**: resolved an issue where the gear manager in classic/camelot perpetually perceived slot 0 as empty and continually attempted to re-equip bag ammo in `frames/gear/highest.lua`. routed inventory queries through `get_inventory_item_link`, corrected `physId` offsets to prevent slot 0 collisions, and added fallback detection for equipped ammo subclasses.
- **ammo equip dstslot taint protection**: guarded slot 0 in `EquipItemByName` within `frames/gear/highest.lua` to route through `C_Container.UseContainerItem(bag, slot)` instead of invalid inventory destination slots, and updated container cursor swaps to target slot 0 via `PickupInventoryItem(0)`.
- **gear manager inventory sync**: updated `frames/gear/engine.lua`, `frames/gear/gear.lua`, and `frames/gear/hammer.lua` to utilize `get_inventory_item_link`, ensuring equipped ammo is accurately recorded in `lastEquippedItems` and properly represented in lock icons.
- **experience & reputation bar texture sync**: ensured experience and reputation bars dynamically track and adopt the global bar texture configured in the options main tab (`frames/themes/engine.lua`, `frames/experience/bar.lua`, `frames/experience/experience.lua`, `frames/experience/reputation.lua`).
- **dungeon journal pins & quest display**: refined pin layout, quest block navigation, and dungeon quest selection in `frames/dungeonjournal/dj_pins.lua`, `frames/dungeonjournal/dj_quests.lua`, and `frames/dungeonjournal/dungeonjournal.lua`.
- **world events combat & secret values**: added safe handling for `issecretvalue()` and in-combat progress bar queries in `frames/quests/modules/q_worldevents.lua`, preventing arithmetic comparison errors on protected widgets.
