# Changelog

## v12.1.0-64 (2026-10-01)

### Features & Major Improvements
- **Target Frame (`frames/bars/target.lua`)**:
  - Implemented dedicated Target Frame for Camelot and Classic with health, power, classification tags (`[Rare]`, `[Boss]`, `+`), level difficulty coloring, and raid target markers.
  - Added additive incoming heal prediction (`healPredBar`) and total absorbs (`absorbBar`) matching player unit frame architecture.
  - Implemented zero-allocation action slot and spellbook range checking.
  - Hardened unit values against engine secret numbers to prevent tainted comparison errors in combat and PvP.

- **Threat Bar (`frames/bars/threat.lua`)**:
  - Added standalone Threat Bar dynamically anchored above the player health bar in Camelot and Classic.
  - Features real-time threat percentages, status colors (aggro, high threat, insecure), and automatic layout re-anchoring with runes and class power bars.

- **Player Health & Heal Prediction (`frames/bars/bars.lua`)**:
  - Registered `UNIT_HEAL_PREDICTION` for immediate player incoming heal updates on cast start.
  - Safeguarded `update_bar0` against secret value comparisons.
  - Added dynamic bar texture synchronization for target and threat frames.

- **Fishing Automation (`frames/fishing.lua`)**:
  - Enhanced bobber detection, audio cue amplification, automated reeling, and one-key cast/reel support.

- **Gear & Stats Enhancements**:
  - Upgraded gear comparison, highest item level tracking, and item cache lookups (`core/items.lua`, `frames/gear/highest.lua`).
  - Added character stats calculation and refined Camelot specialization colorings (`data/stats.lua`, `frames/alts/alts_camelot.lua`).

- **Options & Interface**:
  - Added target frame and threat bar configuration toggles to `SFUI` Bars options tab.
