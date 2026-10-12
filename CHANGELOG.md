# Changelog

## v1.93 (2026-10-12)

### features

- **paladin aura badge**: added a circular aura indicator centered on the top edge of the paladin healthbar in camelot (`frames/bars/bars.lua`) tracking devotion, retribution, concentration, shadow resistance, frost resistance, fire resistance, crusader, and sanctity auras.

### improvements & bug fixes

- **cooldown viewer taint fix**: resolved an `attempted to index a table that cannot be accessed while tainted` error at `CooldownViewer.lua:1700` during target changes (`common.lua`). unmirrored viewers (`EssentialCooldownViewer`, `UtilityCooldownViewer`) are now completely shut down with `:Hide()`, `:UnregisterAllEvents()`, and secure `Show` hooks, and direct property injections on blizzard frame tables were eliminated in favor of local tracking tables.
- **tracked icons viewer scan**: removed unneeded non-aura cooldown viewers from the missing buff scan list (`frames/tracking/trackedicons.lua`).
- **libsharedmedia statusbar registration**: fixed bugsack errors caused by registering blizzard atlas element strings as statusbar files (`core.lua`). statusbar registrations now strictly validate file paths against `C_UIFileAsset.IsKnownFile` before calling `LSM:Register`, and atlas textures are safely resolved directly by sfui.
- **texture dropdown availability**: updated statusbar texture discovery (`core/widgets.lua`) to verify client asset manifests so only available textures appear in the options menu.
- **libsharedmedia update**: synced vendored lib (`Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua`) to upstream revision 181 (12000004).
