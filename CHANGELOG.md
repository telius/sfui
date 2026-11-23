# changelog

## v1.154 (2026-11-23)

### new features & improvements

- **standalone quest automation & reward advisor (`frames/automation/quests.lua`, `frames/options/tabs/tab_automation.lua`, `frames/sync/quests.lua`, `frames/options/tabs/tab_sync.lua`, `config.lua`, `core/module.lua`, `sfui.toc`)**:
  - moved auto quest accept, auto turn-in, smart reward picking, and quest reward advisor badges (`+x% upg`, `+x% off`, `best gold`) out of sync mode into the standalone automation tab so they work independently solo or in groups, with hold-shift pause and dialogueui support.
- **merchant search box (`frames/merchant/merchant.lua`, `frames/merchant/merchant_filter.lua`)**:
  - added a live header search input (`search...`) with quick clear button to filter merchant items by name alongside existing filter dropdown categories.
- **radial rings last-action re-press (`frames/ring/ring.lua`, `frames/ring/ring_live.lua`, `frames/ring/ring_secure.lua`, `frames/options/tabs/tab_ring.lua`)**:
  - pressing a ring's keybind while it is open now immediately triggers the last selected action for that ring during the current session (not persisted across sessions), while `esc` cancels cleanly.
- **copy chat button & popup ux (`frames/chat/chat_frame.lua`, `frames/chat/chat_copy.lua`)**:
  - redesigned the copy chat button as a `20x20` themed micro-button with a pixel-snapped overlapping-pages vector icon, smooth hover/always fade transitions, non-overlapping bottom-right stacking with the scroll-to-bottom button and resize handle, left-click open/close toggle, right-click color-code toggle, and live context-aware tooltips.
  - added `copied to clipboard!` confirmation feedback, dynamic checkbox spacing, read-only user-edit protection, and `nonbattlepet` hyperlink hover tooltip support.

### bug fixes & reliability

- **multi-account sync offline whisper suppression & forever realm checks (`frames/sync/sync.lua`, `frames/sync/codec.lua`)**:
  - prevented `"no player named ..."` whisper error spam when synced peer accounts or alts are offline by tracking offline peer cooldowns, recent whisper targets, and live social/group presence.
  - wired wow forever battle.net same-realm and realm-info checks when resolving whisperable peers.
