---
description: How to bump the addon version for a new release
---

# Version Bump Workflow

When preparing a new release, update the version in **TWO** locations:

## 1. Update sfui.toc (Single Source of Truth)
```
## Version: X.Y.Z
```

## 2. Update CHANGELOG.md
Add a new section at the top:
```markdown
## vX.Y.Z (YYYY-MM-DD)

### Features
- ...

### Bug Fixes
- ...
```

## ⚠️ Important Notes

- **DO NOT** manually edit `config.lua` version - it's automatically synced from the TOC file during `ADDON_LOADED`
- The version in `config.lua` is set to `0.0.0` as a placeholder and gets replaced at runtime

## 3. Commit and Tag
```bash
git add .
git commit -m "chore: Bump version to vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

The GitHub Actions workflow will automatically:
- Package the addon
- Create a GitHub Release
- Upload to CurseForge (if configured)

## Version Numbering

Follow semantic versioning:
- **Major** (X.0.0): Breaking changes, major features
- **Minor** (0.X.0): New features, backward compatible
- **Patch** (0.0.X): Bug fixes, small improvements
