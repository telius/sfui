# Changelog

## v12.1.0-83 (2026-10-08)

### improvements & maintenance

- **repository cleanup & security**: untracked internal agent guidelines (`AGENTS.md`) from git to keep internal prompt configuration and local developer paths private, while preserving the file locally for ide agent tooling.
- **packaging & release optimization**: updated `.pkgmeta` to ignore `.previews`, `docs`, and agent configurations, eliminating over 12 megabytes of preview screenshots and internal documentation from release zip bundles distributed to curseforge, wago, and wowup.
- **gitignore enhancement**: added `AGENTS.md`, `GEMINI.md`, `.agents/`, and editor lockfiles (`~$*`) to `.gitignore` to prevent unintended tracking of temporary or agent configuration files.
- **binding files consolidation**: removed duplicate lowercase binding symlinks (`bindings_camelot.xml`, `bindings_standard.xml`), standardizing on canonical `Bindings_Camelot.xml` and `Bindings_Standard.xml` to prevent file conflicts on case-insensitive filesystems.
- **internal investigation docs relocation**: removed internal debugging report from repository tracking and relocated local notes to `.agent/CDM_CLASSIC_INVESTIGATION.md`.
