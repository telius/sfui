# Changelog

## v1.85 (2026-10-08)

### improvements & bug fixes

- **versioning scheme upgrade**: transitioned to multi-client continuous release versioning (`v1.85`), decoupling addon releases from single blizzard patch cycles while declaring full compatibility across both retail (`120100`) and camelot/classic (`16001`).
- **bag triage runtime crash fix**: fixed boolean argument crash in `frames/options/tabs/tab_classutility.lua` and `core.lua` by validating candidate tables in `execute_purge_candidate` and invoking `ExecutePurge()` cleanly without arguments.
- **cursor item safety**: added busy-cursor safety checks in `frames/automation/triage.lua` and eliminated premature `DeleteCursorItem()` on held cursor items to protect dragged inventory items and spells from accidental deletion.
- **smooth multi-shard purging**: excluded locked container slots from candidate selection in `get_soul_shard_data`, allowing rapid successive keypresses to immediately target the next available excess shard without false "item is locked" errors.
- **hardware key-up debounce**: updated click handlers in `SfuiTriageDeleteBtn` and `SfuiPurgeSoulShards` to guard against duplicate key-up executions on physical keypresses.
- **triage performance & memory optimizations**: implemented fast short-circuiting in `EvaluateTriage` to skip full 140-slot inventory scans when bag space is above threshold, isolated soul shard logic to warlocks, and converted `get_soul_shard_data` to reuse static scratch tables with `wipe()`.
