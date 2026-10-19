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

BUGJAR_PATHS = [
    "/home/james/Games/World of Warcraft/_classic_beta_/WTF/Account/263111#1/SavedVariables/!BugJar.lua",
    "/home/james/Games/World of Warcraft/_retail_/WTF/Account/JMSXL/SavedVariables/!BugJar.lua"
]

SFUI_DIR = "/home/james/projects/sfui"
STATE_FILE = os.path.join(SFUI_DIR, ".agent", "bugjar_state.json")

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
    state = load_state()
    state["last_run"] = int(time.time())

    all_errors = []
    for p in BUGJAR_PATHS:
        errs = parse_bugjar_file(p)
        for e in errs:
            if is_sfui_error(e):
                e["_source_path"] = p
                e["_fingerprint"] = compute_fingerprint(e)
                all_errors.append(e)

    unresolved = [e for e in all_errors if e["_fingerprint"] not in state["resolved"]]

    if not unresolved:
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
        print(f"kind: {kind} | location: {loc}")

        # Check for uncommitted working tree changes
        status_proc = run_cmd(["git", "status", "--porcelain"], check=False)
        has_local_changes = bool(status_proc.stdout.strip())
        stash_created = False

        if has_local_changes:
            print("stashing uncommitted local working tree changes...")
            stash_res = run_cmd(["git", "stash", "push", "-m", "bugjar-autofix-temp-stash"], check=False)
            stash_created = (stash_res.returncode == 0)

        # Pull latest
        run_cmd(["git", "pull", "--rebase", "origin", "main"], check=False)

        # Construct surgical task prompt for agy
        prompt = (
            f"Fix this World of Warcraft Lua error recorded by BugJar for addon 'sfui':\n\n"
            f"- Error Message: {msg}\n"
            f"- Kind: {kind}\n"
            f"- Location: {loc}\n"
            f"- Stack: {stack}\n\n"
            f"Rules and Constraints:\n"
            f"1. Directly inspect the offending code in {SFUI_DIR}.\n"
            f"2. Apply a surgical, minimal fix to handle/prevent this error.\n"
            f"3. Strictly lowercase text in all code comments and chat output.\n"
            f"4. Do NOT touch gamepad code or any gamepad related files/frames.\n"
            f"5. Verify syntax by running `luac -p` on all modified files.\n"
            f"6. Commit the changes directly to branch 'main' with a concise commit message: 'fix(<module>): <description>'.\n"
            f"7. Do NOT bump the version in sfui.toc or edit CHANGELOG.md. Do NOT create git tags or releases.\n"
            f"8. Push the commit to origin main with `git push origin main`.\n"
        )

        try:
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
            print("agy run timed out after 600 seconds.")
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
