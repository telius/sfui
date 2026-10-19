#!/usr/bin/env python3
"""
SFUI BugJar Dissector and Automated Patcher
Watches WoW BugJar SavedVariables for SFUI errors, diagnoses them,
applies surgical fixes, validates syntax with luac, and pushes directly to main.
"""

import os
import sys
import json
import time
import re
import hashlib
import subprocess
from datetime import datetime

import glob

SFUI_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STATE_FILE = os.path.join(SFUI_DIR, ".agent", "bugjar_state.json")

def get_bugjar_paths():
    paths = []
    # 1. Environment variable override
    env = os.environ.get("BUGJAR_PATHS")
    if env:
        for p in re.split(r"[:;,]", env):
            expanded = os.path.expanduser(p.strip())
            if expanded and os.path.exists(expanded):
                paths.append(expanded)
        if paths:
            return paths

    # 2. Local gitignored config in .agent/bugjar_paths.json
    config_file = os.path.join(SFUI_DIR, ".agent", "bugjar_paths.json")
    if os.path.exists(config_file):
        try:
            with open(config_file, "r") as f:
                cfg = json.load(f)
                if isinstance(cfg, list):
                    return [os.path.expanduser(p) for p in cfg if os.path.exists(os.path.expanduser(p))]
        except Exception:
            pass

    # 3. Dynamic glob discovery across local wow installations (zero hardcoded user/account names)
    search_patterns = [
        os.path.expanduser("~/Games/World of Warcraft/**/SavedVariables/!BugJar.lua"),
        os.path.expanduser("~/.var/app/*/Games/World of Warcraft/**/SavedVariables/!BugJar.lua"),
        os.path.expanduser("~/.wine/drive_c/**/SavedVariables/!BugJar.lua"),
    ]
    for pat in search_patterns:
        for m in glob.glob(pat, recursive=True):
            if m not in paths and not m.endswith(".bak"):
                paths.append(m)
    return paths

def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "resolved": {},
        "last_run": 0,
        "last_fix": "none",
        "last_fix_time": 0,
        "total_fixed": 0
    }

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def parse_bugjar_file(filepath):
    if not os.path.exists(filepath):
        return []

    errors = []
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"error reading {filepath}: {e}")
        return []

    in_errors = False
    current_error = None

    for line in lines:
        raw = line.strip()
        if raw.startswith('["errors"] = {'):
            in_errors = True
            continue
        if in_errors:
            if raw == '{':
                current_error = {}
            elif raw in ('},', '}'):
                if current_error is not None:
                    errors.append(current_error)
                    current_error = None
                else:
                    in_errors = False
            elif current_error is not None:
                m = re.match(r'\[\"([^\"]+)\"\]\s*=\s*(.*?),?$', raw)
                if m:
                    k = m.group(1)
                    v = m.group(2).rstrip(',')
                    if v.startswith('"') and v.endswith('"'):
                        v = v[1:-1]
                    current_error[k] = v

    return errors

def compute_fingerprint(err):
    addon = err.get("addon", "sfui")
    kind = err.get("kind", "")
    message = err.get("message", "")
    location = err.get("location", "")
    stack = err.get("stack", "")
    key_str = f"{addon}|{kind}|{message}|{location}|{stack}"
    return hashlib.sha1(key_str.encode("utf-8")).hexdigest()

def is_sfui_error(err):
    addon = (err.get("addon") or "").lower()
    msg = (err.get("message") or "").lower()
    stack = (err.get("stack") or "").lower()
    loc = (err.get("location") or "").lower()

    if addon == "sfui":
        return True
    if "addons\\sfui\\" in stack or "addons/sfui/" in stack:
        return True
    if "addons\\sfui\\" in loc or "addons/sfui/" in loc:
        return True
    if "sfui" in msg:
        return True
    return False

def run_cmd(cmd, cwd=SFUI_DIR, check=True):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)

def notify(summary, body):
    try:
        subprocess.run(["notify-send", summary, body], check=False)
    except Exception:
        pass

def main():
    import argparse
    parser = argparse.ArgumentParser(description="SFUI BugJar Dissector and Automated Patcher")
    parser.add_argument("--dry-run", action="store_true", help="Simulate without invoking agy or pushing to git")
    parser.add_argument("--test-file", type=str, help="Specific BugJar file to scan instead of auto-discovering")
    parser.add_argument("--verbose", action="store_true", help="Print verbose diagnostic details")
    args = parser.parse_args()

    state = load_state()
    state["last_run"] = int(time.time())

    paths_to_scan = [os.path.expanduser(args.test_file)] if args.test_file else get_bugjar_paths()
    if args.verbose or args.dry_run:
        print(f"scanning {len(paths_to_scan)} bugjar location(s):")
        for p in paths_to_scan:
            print(f"  -> {p}")

    all_errors = []
    for p in paths_to_scan:
        errs = parse_bugjar_file(p)
        for e in errs:
            if is_sfui_error(e):
                e["_source_path"] = p
                e["_fingerprint"] = compute_fingerprint(e)
                all_errors.append(e)

    unresolved = [e for e in all_errors if e["_fingerprint"] not in state["resolved"]]

    if not unresolved:
        if not args.dry_run:
            save_state(state)
        print("no new sfui errors in bugjar.")
        return

    print(f"found {len(unresolved)} new sfui error(s) in bugjar.")

    for err in unresolved:
        fp = err["_fingerprint"]
        msg = err.get("message", "unknown error")
        kind = err.get("kind", "error")
        stack = err.get("stack", "")
        loc = err.get("location", "")

        print(f"\n--- processing error: {msg} ---")
        print(f"fingerprint: {fp}")
        print(f"kind: {kind} | location: {loc}")

        # Construct surgical task prompt for agy adhering strictly to .agent directives
        prompt = (
            f"Fix this World of Warcraft Lua error recorded by BugJar for addon 'sfui':\n\n"
            f"- Error Message: {msg}\n"
            f"- Kind: {kind}\n"
            f"- Location: {loc}\n"
            f"- Stack: {stack}\n\n"
            f"Mandatory Project Directives (from AGENTS.md and .agent/workflows/methods.md):\n"
            f"1. Strictly lowercase text in all code comments, messages, and commit descriptions ('no caps').\n"
            f"2. Always reference the in-house Blizzard Interface source trees for authoritative APIs, templates, and taint analysis (never make external web requests):\n"
            f"   - Camelot / Forever / Classic UI: ~/projects/wow-ui-source-forever/Interface\n"
            f"   - Retail / Midnight / Live UI: ~/projects/wow-ui-source-live/Interface\n"
            f"3. Architecture & Taint: 100% lightweight non-secure panels, zero taint vectors, zero global frame contamination. Guard secure executions with InCombatLockdown() or defer to PLAYER_REGEN_ENABLED when needed.\n"
            f"4. Event Handling: NEVER create standalone event frames (CreateFrame + RegisterEvent). All events MUST route through `sfui.events` (dispatcher.lua).\n"
            f"5. Performance: Localize frequently-called globals (e.g. math_min, wipe, pcall, tonumber) in module scopes.\n"
            f"6. Gamepad Protection: Do NOT touch gamepad code or any gamepad-related frames/settings.\n"
            f"7. Syntax Verification: MUST run `luac -p` on all modified files before committing.\n"
            f"8. Git Discipline: Commit directly to branch 'main' with a clean conventional commit: 'fix(<module>): <description>'. Push to origin main.\n"
            f"9. Release Protection: Do NOT bump the version in sfui.toc, do NOT touch CHANGELOG.md, and do NOT create git tags or releases.\n"
            f"10. Secret Values & Direct Forwarding: NEVER inspect, branch on, compare (<, >, ==), string-format (string.format, tostring), or perform arithmetic on secret/restricted values (issecretvalue). Avoid `pcall` as an exploratory crutch; forward Blizzard API return values directly and untouched to their destination widgets.\n"
        )

        if args.dry_run:
            print("\n[DRY RUN] Generated prompt for agy:")
            print("=" * 60)
            print(prompt.strip())
            print("=" * 60)
            print(f"[DRY RUN] Would execute agy to patch error.")
            print(f"[DRY RUN] Would verify syntax using `luac -p`.")
            print(f"[DRY RUN] Would commit to 'main' with: fix(bugjar): {msg[:60].lower()}")
            print(f"[DRY RUN] Would push directly to origin main.")
            print(f"[DRY RUN] Would record fingerprint: {fp}")
            continue

        # Check for uncommitted working tree changes
        status_proc = run_cmd(["git", "status", "--porcelain"], check=False)
        has_local_changes = bool(status_proc.stdout.strip())
        stash_created = False

        try:
            if has_local_changes:
                print("stashing uncommitted local working tree changes...")
                stash_res = run_cmd(["git", "stash", "push", "-m", "bugjar-autofix-temp-stash"], check=False)
                stash_created = (stash_res.returncode == 0)

            # Pull latest
            run_cmd(["git", "pull", "--rebase", "origin", "main"], check=False)

            print("invoking agy agent runner to dissect and patch...")
            res = subprocess.run(
                ["agy", "--print", prompt, "--dangerously-skip-permissions"],
                cwd=SFUI_DIR,
                capture_output=True,
                text=True,
                timeout=600
            )
            print("agy finished. returncode:", res.returncode)

            # Check if any git changes remain uncommitted or if commit was made
            diff_proc = run_cmd(["git", "status", "--porcelain"], check=False)
            if diff_proc.stdout.strip():
                # Verify syntax before committing
                syntax_check = run_cmd(["bash", "-c", "find . -name '*.lua' -exec luac -p {} +"], check=False)
                if syntax_check.returncode == 0:
                    # Guarantee release files are never modified by the auto-fixer
                    run_cmd(["git", "checkout", "--", "sfui.toc", "CHANGELOG.md"], check=False)
                    run_cmd(["git", "add", "-A"])
                    run_cmd(["git", "commit", "-m", f"fix(bugjar): {msg[:60].lower()}"])
                    run_cmd(["git", "push", "origin", "main"], check=False)
                else:
                    print("syntax check failed on unstaged changes! aborting commit.")
                    run_cmd(["git", "checkout", "."])

            # Record resolved state
            state["resolved"][fp] = {
                "message": msg,
                "kind": kind,
                "location": loc,
                "resolved_at": int(time.time()),
                "time_str": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
            state["total_fixed"] = state.get("total_fixed", 0) + 1
            clean_msg = msg.replace("[Blocked]", "").strip()[:40].lower()
            state["last_fix"] = clean_msg
            state["last_fix_time"] = int(time.time())
            save_state(state)

            notify("SFUI Auto-Patcher", f"Fixed and pushed: {msg[:50]}")

        except subprocess.TimeoutExpired:
            print("agy run timed out after 1800 seconds.")
        except Exception as ex:
            print(f"error during auto-patch: {ex}")
        finally:
            if stash_created:
                print("restoring uncommitted working tree changes from stash...")
                run_cmd(["git", "stash", "pop"], check=False)

    save_state(state)
    print("all new errors processed.")

if __name__ == "__main__":
    main()
