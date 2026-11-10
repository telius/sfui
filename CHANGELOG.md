# changelog

## v1.145 (2026-11-10)

### new features & improvements

- **multi-account sync quest completion notifications (`frames/sync/merge.lua`, `frames/sync/sync.lua`, `frames/options/tabs/tab_sync.lua`)**:
  - extended `DELTA_QUEST_PROG` (`merge.ScanActiveQuestsDelta` and `merge.MergeQuestProgDelta`) to detect live quest completion transitions (`0 -> 1` objectives complete / ready for turn-in and newly turned-in quests) on synced peers.
  - added `notify_peer_quest_completed` in `frames/sync/sync.lua` to notify the active client via screen banner (`UIErrorsFrame`), chat printout, and quest-complete audio cue when a non-active synced client completes a quest.
- **auto-quest item reward guard (`frames/sync/quests.lua`, `frames/options/tabs/tab_sync.lua`)**:
  - updated `on_quest_complete` and `drain_pending_dialogs` in `frames/sync/quests.lua` so quests are only auto-completed (`GetQuestReward`) when both `GetNumQuestChoices()` and `GetNumQuestRewards()` are `0`.
  - quests that offer choice or fixed item rewards now stop at the reward panel for manual confirmation while still pre-highlighting the suggested choice when multiple options exist.
