# changelog

## v1.132 (2026-11-02)

### features & improvements

- **frost death knight runeforge & talent weapon solver (`frames/gear/highest/solvers.lua`, `frames/gear/highest/tooltips.lua`, `frames/gear/highest/executor.lua`, `frames/gear/highest.lua`, `frames/gear/highest/validator.lua`)**:
  - added off-hand rune of razorice (`3370`) selection when frostbane (`455993`) is talented and the main-hand weapon (`slot 16`) is locked to a non-razorice runeforge (such as rune of the fallen crusader `3368`).
  - added breath of sindragosa (`1249658` / `152279`) talent detection and `HasStoneskinGargoyleEnchant` (`3847` / `62158`) scanner so the weapon solver automatically equips the best 1h weapon with rune of the stoneskin gargoyle in the off-hand (`slot 17`).
  - updated the identical-item swap guard in `EquipHighestILvl` (`frames/gear/highest/executor.lua`) to compare enchant ids and honor `equipReason` so identical `itemID` weapons with different runeforges are never skipped.
- **retail bonus roll tracking & loot browser integration (`frames/gear/bonusroll.lua`)**:
  - preserved persisted `db.used` bonus-rolled item state across logins instead of wiping on uncached item tooltips at `PLAYER_ENTERING_WORLD`, and added automatic `GET_ITEM_INFO_RECEIVED` retry scanning.
  - added static midnight season 1 (`The Voidspire`, `The Dreamrift`, `March on Quel'Danas`, and `Ulu'ura` / `Kith'ix` world bosses, including kith'ix chest `286019`) item-to-boss mapping table (`ITEM_TO_BOSS`) alongside dynamic encounter journal (`C_EncounterJournal`) fallback scanning.
  - hooked `BonusRollFrame.PromptFrame.RollButton` and `CHAT_MSG_LOOT` / `SPELL_CONFIRMATION_PROMPT` to record rolled encounters immediately and refresh the loot browser (`frames/gear/lootviewer.lua`).
