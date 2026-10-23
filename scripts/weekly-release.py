#!/usr/bin/env python3
"""
sfui weekly automated release script
checks for qualifying fix(bugjar): commits that have passed the soak period (default: 24h).
if found, bumps version in sfui.toc, generates CHANGELOG.md, commits, tags, and pushes.
"""

import os
import sys
import re
import argparse
import subprocess
from datetime import datetime

SFUI_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TOC_FILE = os.path.join(SFUI_DIR, "sfui.toc")
CHANGELOG_FILE = os.path.join(SFUI_DIR, "CHANGELOG.md")

def run_cmd(cmd, cwd=SFUI_DIR, check=True):
    res = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        print(f"error running {' '.join(cmd)}:\n{res.stderr}", file=sys.stderr)
        sys.exit(res.returncode)
    return res

def set_github_output(key, value):
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output and os.path.exists(gh_output):
        with open(gh_output, "a") as f:
            f.write(f"{key}={value}\n")

def get_latest_tag():
    res = run_cmd(["git", "describe", "--tags", "--abbrev=0"], check=False)
    if res.returncode == 0:
        return res.stdout.strip()
    return None

def get_qualifying_commits(soak_hours=24, force=False):
    latest_tag = get_latest_tag()
    commit_range = f"{latest_tag}..HEAD" if latest_tag else "HEAD"
    
    cmd = ["git", "log", commit_range, "-E", "--grep=^fix(\\([^)]+\\))?:", "--format=%H|||%s"]
    if not force and soak_hours > 0:
        cmd.append(f"--until={soak_hours} hours ago")
        
    res = run_cmd(cmd, check=False)
    if res.returncode != 0 or not res.stdout.strip():
        return latest_tag, []
        
    lines = [l.strip() for l in res.stdout.strip().split("\n") if l.strip()]
    commits = []
    for line in lines:
        parts = line.split("|||", 1)
        if len(parts) == 2:
            commit_hash = parts[0]
            subject = parts[1]
            commits.append({"hash": commit_hash, "subject": subject})
    return latest_tag, commits

def get_next_version():
    with open(TOC_FILE, "r", encoding="utf-8") as f:
        content = f.read()
    
    m = re.search(r"##\s*Version:\s*v(\d+)\.(\d+)", content)
    if not m:
        raise ValueError(f"could not parse ## Version in {TOC_FILE}")
    
    major = int(m.group(1))
    minor = int(m.group(2))
    next_minor = minor + 1
    next_version = f"v{major}.{next_minor}"
    return f"v{major}.{minor}", next_version

def build_changelog(next_version, commits):
    today = datetime.now().strftime("%Y-%m-%d")
    header = f"# changelog\n\n## {next_version} ({today})\n\n### improvements & bug fixes\n\n- **automated bugjar fixes**:\n"
    
    items = []
    seen = set()
    for c in commits:
        subj = c["subject"]
        # remove prefix fix(bugjar): or format fix(<module>): cleanly
        clean = re.sub(r"^fix\(bugjar\):\s*", "", subj, flags=re.IGNORECASE).strip()
        clean = re.sub(r"^fix\(([^)]+)\):\s*", r"**\1**: ", clean, flags=re.IGNORECASE).strip()
        clean = re.sub(r"^fix:\s*", "", clean, flags=re.IGNORECASE).strip()
        clean = clean.lower()
        if clean and clean not in seen:
            seen.add(clean)
            # wrap relative paths in backticks if not already
            def wrap_path(match):
                path = match.group(0)
                return f"`{path}`"
            clean = re.sub(r"(?<!`)([\w\-]+(?:/[\w\-]+)+\.lua)(?!`)", wrap_path, clean)
            items.append(f"  - {clean}")
            
    if not items:
        items.append("  - automated bug fixes and stability improvements.")
        
    return header + "\n".join(items) + "\n"

def main():
    parser = argparse.ArgumentParser(description="sfui weekly automated release")
    parser.add_argument("--soak-hours", type=int, default=24, help="minimum hours since commit (default: 24)")
    parser.add_argument("--dry-run", action="store_true", help="preview changes without modifying files or git")
    parser.add_argument("--force", action="store_true", help="ignore soak hours filter")
    parser.add_argument("--push", action="store_true", help="push commit and tag to origin main")
    args = parser.parse_args()

    latest_tag, commits = get_qualifying_commits(soak_hours=args.soak_hours, force=args.force)
    print(f"latest tag: {latest_tag or 'none'}")
    print(f"found {len(commits)} qualifying autofixer commit(s) (soak: {args.soak_hours}h, force: {args.force})")
    
    if not commits:
        print("no qualifying autofixer commits found. exiting.")
        set_github_output("release_created", "false")
        sys.exit(0)

    for c in commits:
        print(f"  [{c['hash'][:7]}] {c['subject']}")

    current_ver, next_ver = get_next_version()
    print(f"version bump: {current_ver} -> {next_ver}")

    new_changelog = build_changelog(next_ver, commits)

    if args.dry_run:
        print("\n--- dry-run changelog preview ---")
        print(new_changelog)
        print("--- end preview ---")
        set_github_output("release_created", "true")
        set_github_output("release_version", next_ver)
        return

    # 1. Update sfui.toc
    with open(TOC_FILE, "r", encoding="utf-8") as f:
        toc_content = f.read()
    new_toc = re.sub(r"(##\s*Version:\s*)v\d+\.\d+", rf"\g<1>{next_ver}", toc_content)
    with open(TOC_FILE, "w", encoding="utf-8") as f:
        f.write(new_toc)
    print(f"updated {TOC_FILE} to {next_ver}")

    # 2. Update CHANGELOG.md (overwrite current only)
    with open(CHANGELOG_FILE, "w", encoding="utf-8") as f:
        f.write(new_changelog)
    print(f"updated {CHANGELOG_FILE}")

    # 3. Git commit & tag
    name_check = run_cmd(["git", "config", "user.name"], check=False)
    if not name_check.stdout.strip():
        run_cmd(["git", "config", "user.name", "github-actions[bot]"])
        run_cmd(["git", "config", "user.email", "github-actions[bot]@users.noreply.github.com"])

    run_cmd(["git", "add", "sfui.toc", "CHANGELOG.md"])
    commit_msg = f"chore: Bump version to {next_ver}"
    run_cmd(["git", "commit", "-m", commit_msg])
    run_cmd(["git", "tag", next_ver])
    print(f"created commit and tag: {next_ver}")

    # 4. Optional push
    if args.push:
        run_cmd(["git", "push", "origin", "main", next_ver])
        print(f"pushed main and tag {next_ver} to origin")

    set_github_output("release_created", "true")
    set_github_output("release_version", next_ver)

if __name__ == "__main__":
    main()
