# Changelog

## v12.1.0-72 (2026-10-05)

### Features & Major Improvements

- **Merchant Subsystem Modularization (`frames/merchant/`, `sfui.toc`)**:
  - **Modular Architecture**: Split the monolithic merchant implementation into three focused, maintainable modules under `frames/merchant/`:
    - `frames/merchant/merchant_filter.lua`: Data modeling, table pooling, filter pipelines (known spells, usable items, class and armor proficiency filters, search queries), and grimoire tracking.
    - `frames/merchant/merchant_utility.lua`: Stack-split popup dialog, currency footer, and utility action bar (automatic/manual repairs, junk selling, and filter mode toggles).
    - `frames/merchant/merchant.lua`: High-strata window container, 4x7 grid buttons, scrollbar, header portrait and title, and event dispatcher wiring.
  - **TOC Sequence**: Sequenced load order in `sfui.toc` to guarantee clean dependency resolution (`merchant_filter.lua` -> `merchant_utility.lua` -> `merchant.lua`).

- **Warlock Pet Grimoire Filtering for Inactive Pets (`frames/merchant/merchant_filter.lua`, `frames/merchant/merchant.lua`)**:
  - **Cross-Pet Spell Tracking**: Resolved Demon Trainer issue on Camelot where pet grimoires only registered as "Already known" when that specific demon was currently summoned.
  - **Persistent Pet Spell Cache**: Learned pet spell ranks are cached in `SfuiDB.petSpells[playerGUID][spellName]` to accurately track known spells across all pet summons.
  - **Zero Merchant Interaction Overhead**: Pet spellbooks are scanned exclusively on `PET_SPELL_UPDATE` and `UNIT_PET` events when a pet is summoned or updated, eliminating redundant rescanning on merchant open, filter changes, and scrolling.
  - **Strict Class & Client Gating**: Processing is strictly gated behind `sfui.isCamelot` and `playerClass == "WARLOCK"`, bypassing all logic for other classes and retail.
  - **Fast Grimoire Fast-Path**: Non-grimoire items bypass parsing via a fast substring search (`link:find("Grimoire", 1, true)`), avoiding tooltip extraction overhead.
  - **Tooltip Indicator**: Rendered red "Already known" status line on merchant item tooltips when hovering over grimoires for inactive pets.

- **Project-Wide `isForever` Deprecation & Consolidation (`compat.lua`, `common.lua`, etc.)**:
  - **Clean Client Standard**: Completely purged deprecated `isForever`, `IS_WOW_FOREVER`, `is_wow_forever`, and `wow_forever` symbols across the entire repository.
  - **Unified Compatibility API**: Consolidated all client branch detection and compatibility flags onto `sfui.isCamelot`, `sfui.compat.is_camelot`, `sfui.compat.has.camelot`, and `sfui.version.camelot` in `compat.lua`.
  - **Consumer Alignment**: Updated all references across `core/bridge.lua`, `core/items.lua`, `core/talents_camelot.lua`, `core/talents_standard.lua`, `frames/alts/alts_camelot.lua`, `frames/automation/rankup.lua`, `frames/themes/camelot.lua`, `frames/themes/modern.lua`, `frames/themes/engine.lua`, `frames/bars/threat.lua`, `frames/bars/target.lua`, `frames/bars/bars.lua`, `frames/gear/highest.lua`, `frames/quests/engine/q_tracker.lua`, `frames/quests/helpers/q_timerbars.lua`, `frames/quests/modules/q_camelot_class.lua`, `frames/quests/modules/q_camelot_skills.lua`, and `frames/quests/modules/q_camelot.lua`.
