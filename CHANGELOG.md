# changelog

## v1.128 (2026-10-31)

### features & improvements

- **sync party hud durability (`frames/sync/hud.lua`)**:
  - added equipped item durability scanning (`compute_local_durability` across slots `1..18` via `GetInventoryItemDurability` with `issecretvalue` guards) reporting the lowest slot durability percentage.
  - persisted durability to `SfuiDB.alts[guid].durability` and broadcast live updates via `DELTA_HUD_STATS` (`d = dur`) on `UPDATE_INVENTORY_DURABILITY`.
  - added a color-coded durability badge column (`row.durFs`) alongside free bag slots on each sync hud row and included durability details in row and footer tooltips.
