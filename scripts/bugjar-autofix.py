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

    # 3. Dynamic glob discovery across local wow installations (prioritizing sfuibug then !BugJar)
    search_patterns = [
        os.path.expanduser("~/Games/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/sfuibug.lua"),
        os.path.expanduser("~/Games/World of Warcraft/_retail_/WTF/Account/*/SavedVariables/sfuibug.lua"),
        os.path.expanduser("~/Games/World of Warcraft/_*/WTF/Account/*/SavedVariables/sfuibug.lua"),
        os.path.expanduser("~/Games/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/!BugJar.lua"),
        os.path.expanduser("~/Games/World of Warcraft/_retail_/WTF/Account/*/SavedVariables/!BugJar.lua"),
        os.path.expanduser("~/Games/World of Warcraft/_*/WTF/Account/*/SavedVariables/!BugJar.lua"),
        os.path.expanduser("~/.var/app/*/Games/World of Warcraft/_*/WTF/Account/*/SavedVariables/!BugJar.lua"),
        os.path.expanduser("~/.wine/drive_c/**/World of Warcraft/_*/WTF/Account/*/SavedVariables/!BugJar.lua"),
    ]
    for pat in search_patterns:
        for m in glob.glob(pat, recursive=True):
            if "/_classic_beta_/" in m:
                continue
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

def unescape_lua_string(s):
    if not isinstance(s, str):
        return ""
    return re.sub(
        r'\\(\\|n|r|t|"|\')',
        lambda m: {
            "\\": "\\",
            "n": "\n",
            "r": "\r",
            "t": "\t",
            '"': '"',
            "'": "'",
        }[m.group(1)],
        s,
    )


def build_sfui_source_index():
    rel_paths = set()
    basename_counts = {}
    corpus_parts = []
    generic_names = {"core.lua", "init.lua", "config.lua", "util.lua", "utils.lua", "main.lua"}

    for root, dirs, files in os.walk(SFUI_DIR):
        dirs[:] = [d for d in dirs if d not in (".git", ".agent", "scripts", ".github")]
        for fname in files:
            if fname.endswith((".lua", ".xml")):
                full_path = os.path.join(root, fname)
                rel = os.path.relpath(full_path, SFUI_DIR).replace("\\", "/").lower()
                rel_paths.add(rel)
                bname = fname.lower()
                basename_counts[bname] = basename_counts.get(bname, 0) + 1
                if fname.endswith(".lua"):
                    try:
                        with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                            corpus_parts.append(f.read().lower())
                    except Exception:
                        pass

    unique_basenames = {
        b for b, count in basename_counts.items()
        if count == 1 and b not in generic_names
    }
    return rel_paths, unique_basenames, "\n".join(corpus_parts)


SFUI_REL_PATHS, SFUI_UNIQUE_BASENAMES, SFUI_SOURCE_CORPUS = build_sfui_source_index()


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
    raw_error = None

    for line in lines:
        raw = line.strip()
        if raw.startswith('["errors"] = {'):
            in_errors = True
            continue
        if in_errors:
            if raw == '{':
                current_error = {}
                raw_error = {}
            elif raw in ('},', '}'):
                if current_error is not None:
                    current_error["_raw"] = raw_error
                    errors.append(current_error)
                    current_error = None
                    raw_error = None
                else:
                    in_errors = False
            elif current_error is not None:
                m = re.match(r'\[\"([^\"]+)\"\]\s*=\s*(.*?),?$', raw)
                if m:
                    k = m.group(1)
                    v = m.group(2).rstrip(',')
                    if v.startswith('"') and v.endswith('"'):
                        v = v[1:-1]
                    raw_error[k] = v
                    current_error[k] = unescape_lua_string(v)

    return errors


def parse_sfuibug_file(filepath):
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
            if re.match(r'\[\"[a-f0-9]+\"\]\s*=\s*\{', raw):
                current_error = {
                    "addon": "sfui",
                    "source": "sfuibug",
                    "kind": "error",
                }
            elif raw in ('},', '}'):
                if current_error is not None:
                    # Recover crash file/line from stack if legacy entry had file="unknown"
                    c_file = current_error.get("file", "unknown")
                    c_line = current_error.get("line", "0")
                    if (c_file == "unknown" or str(c_line) == "0") and current_error.get("stack"):
                        for stk_line in current_error["stack"].splitlines():
                            m_stk = re.search(r"([A-Za-z0-9_/\-]+?\.lua)[\"\]]*:(\d+)", stk_line)
                            if m_stk:
                                cand_f = re.sub(r"^.*?AddOns/sfui/", "", m_stk.group(1), flags=re.IGNORECASE)
                                if not cand_f.lower().startswith("blizzard_") and cand_f not in ("dispatcher.lua", "sfuibug.lua"):
                                    if c_file == "unknown":
                                        current_error["file"] = cand_f
                                    if str(c_line) == "0":
                                        current_error["line"] = m_stk.group(2)
                                    break
                    if "file" in current_error and "line" in current_error:
                        current_error["location"] = f"{current_error['file']}:{current_error['line']}"
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
                    current_error[k] = unescape_lua_string(v)

    return errors


def compute_fingerprint(err):
    if err.get("source") == "sfuibug" and err.get("fingerprint"):
        return f"sfuibug:{err['fingerprint']}"
    addon = err.get("addon", "sfui")
    kind = err.get("kind", "")
    message = err.get("message", "")
    location = err.get("location", "")
    stack = err.get("stack", "")
    key_str = f"{addon}|{kind}|{message}|{location}|{stack}"
    return hashlib.sha1(key_str.encode("utf-8")).hexdigest()


def is_sfui_error(err):
    """
    Strictly determine whether an error record was genuinely caused by sfui.
    Returns (is_sfui: bool, reason: str).
    """
    if err.get("source") == "sfuibug":
        mod = err.get("module", "core")
        loc = err.get("location", "")
        return True, f"verified sfuibug record [{mod}] at {loc}"
    addon = (err.get("addon") or "").strip().lower()
    msg = err.get("message") or ""
    stack = err.get("stack") or ""
    loc = (err.get("location") or "").strip()
    kind = (err.get("kind") or "").strip().lower()
    combined = f"{stack}\n{msg}"

    # 1. BugJar's own stack/message attribution must explicitly blame 'sfui'.
    #    Reject errors attributed to 'Blizzard UI', 'ElvUI', 'Details', 'Macros',
    #    'Unknown', or any other third-party addon (even if msg mentions
    #    "(execution tainted by 'sfui')" due to ambient Midnight taint).
    if addon != "sfui":
        return False, f"attributed to '{err.get('addon') or 'unknown'}', not sfui"

    # 2. Inspect all AddOns/<Name>/ references in stack and message from top to bottom.
    #    Ignore '!BugJar' and 'Blizzard_*'. If another third-party addon appears
    #    before 'sfui', that addon is the primary culprit in the call chain.
    addon_refs = re.findall(
        r"(?:Interface[/\\]+)?AddOns[/\\]+([^/\\:\"\'\s\]]+)",
        combined,
        re.IGNORECASE,
    )
    non_blizz_addons = [
        a.lower() for a in addon_refs
        if a.lower() != "!bugjar" and not a.lower().startswith("blizzard_")
    ]
    if non_blizz_addons and non_blizz_addons[0] != "sfui":
        return False, f"third-party addon '{non_blizz_addons[0]}' precedes sfui in stack"

    other_third_party = [a for a in non_blizz_addons if a != "sfui"]
    if other_third_party:
        return False, f"contaminated by third-party addon(s) in stack: {', '.join( sorted(set(other_third_party)) )}"

    # 3. Check for an explicit sfui source file path (AddOns/sfui/<path>.lua) in stack or message.
    sfui_file_matches = re.findall(
        r"AddOns[/\\]+sfui[/\\]+([^:\"\'\n\r\]]+?\.(?:lua|xml))",
        combined,
        re.IGNORECASE,
    )
    for rel_match in sfui_file_matches:
        norm_rel = rel_match.replace("\\", "/").lstrip("/").lower()
        if norm_rel in SFUI_REL_PATHS:
            return True, f"verified sfui source file '{norm_rel}' in stack/message"

    # 4. If location is present (e.g. "ring_worldmarkers.lua:41" or "TextStatusBar.lua:110"),
    #    verify that location is an actual sfui file and NOT a Blizzard or third-party file.
    if loc:
        loc_file = loc.split(":", 1)[0].strip().replace("\\", "/").lower()
        if loc_file in SFUI_REL_PATHS:
            return True, f"verified sfui location '{loc}'"
        if loc_file in SFUI_UNIQUE_BASENAMES:
            # Ensure location isn't actually inside Blizzard_* or another addon in the message/stack
            if not re.search(
                r"AddOns[/\\]+(?!sfui[/\\])[^/\\]+[/\\]+[^\n\r]*?" + re.escape(loc_file),
                combined,
                re.IGNORECASE,
            ):
                return True, f"verified unique sfui file basename '{loc_file}' at '{loc}'"
        return False, f"location '{loc}' is outside sfui with no sfui frame in stack"

    # 5. Stackless taint events (e.g. "[Blocked] sfui tried to call the protected function 'X'.").
    #    WoW's ADDON_ACTION_BLOCKED event provides no stack trace or file:line, and often
    #    blames an addon for ambient EditMode / Blizzard action bar calls (like SetPointBase).
    #    Only accept if the blocked call target actually exists in sfui's Lua source code.
    if kind == "taint":
        m_blocked = re.search(
            r"tried to call the protected function ['\"]([^'\"]+)['\"]",
            msg,
            re.IGNORECASE,
        )
        if m_blocked:
            target_clean = re.sub(r"\(\)$", "", m_blocked.group(1).strip()).lower()
            if ":" in target_clean:
                # Require literal 'frame:method' call in sfui source for stackless taint events
                if target_clean in SFUI_SOURCE_CORPUS:
                    return True, f"taint target '{target_clean}' matched in sfui source"
                return False, f"stackless taint for '{target_clean}' not called directly by sfui"
            elif "." in target_clean:
                if target_clean in SFUI_SOURCE_CORPUS:
                    return True, f"taint target '{target_clean}' matched in sfui source"
                return False, f"stackless taint for '{target_clean}' not called by sfui"
            else:
                if re.search(r"\b" + re.escape(target_clean) + r"\s*\(", SFUI_SOURCE_CORPUS):
                    return True, f"taint function '{target_clean}(' matched in sfui source"
                return False, f"stackless taint function '{target_clean}' not called by sfui"
        return False, "stackless taint event with no verifiable sfui call site"

    return False, "no verifiable sfui file or stack frame found"

def run_cmd(cmd, cwd=SFUI_DIR, check=True):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=check)

def notify(summary, body):
    try:
        subprocess.run(["notify-send", summary, body], check=False)
    except Exception:
        pass

def get_best_high_model():
    default_model = "gemini-4-argon-high"
    try:
        res = subprocess.run(["agy", "models"], capture_output=True, text=True, timeout=10, check=False)
        candidates = []
        for line in res.stdout.splitlines():
            m = re.search(r"(gemini-(\d+(?:\.\d+)?)-[a-z0-9-]+-high)\b", line.strip())
            if m:
                model_id = m.group(1)
                ver = float(m.group(2))
                is_non_flash = 0 if "flash" in model_id else 1
                candidates.append((ver, is_non_flash, model_id))
        if candidates:
            candidates.sort(reverse=True)
            return candidates[0][2]
    except Exception:
        pass
    return default_model

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
        if "sfuibug.lua" in p:
            errs = parse_sfuibug_file(p)
        else:
            errs = parse_bugjar_file(p)
        for e in errs:
            matched, reason = is_sfui_error(e)
            if matched:
                e["_source_path"] = p
                e["_fingerprint"] = compute_fingerprint(e)
                e["_raw_fingerprint"] = compute_fingerprint(e.get("_raw", e))
                e["_match_reason"] = reason
                all_errors.append(e)
            elif args.verbose or args.dry_run:
                short_msg = (e.get("message") or "unknown").splitlines()[0][:80]
                print(f"  [skip non-sfui] ({reason}): {short_msg}")

    unresolved = [
        e for e in all_errors
        if e["_fingerprint"] not in state["resolved"]
        and e.get("_raw_fingerprint") not in state["resolved"]
    ]

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
        reason = err.get("_match_reason", "")
        func_name = err.get("func", "")
        dispatch_kind = err.get("dispatch_kind", "")
        event_name = err.get("event", "")
        dispatch_args = err.get("args", "")
        registered_at = err.get("registered_at", "")
        caller_site = err.get("caller", "")
        locals_dump = err.get("locals", "")
        in_combat = err.get("in_combat", "")
        client_ver = err.get("client_version", "")

        print(f"\n--- processing error: {msg} ---")
        print(f"fingerprint: {fp}")
        print(f"kind: {kind} | location: {loc} | attribution: {reason}")

        extra_ctx_lines = []
        if func_name:
            extra_ctx_lines.append(f"- Function: {func_name}")
        if dispatch_kind or (event_name and event_name != "none"):
            extra_ctx_lines.append(f"- Dispatch Context: {dispatch_kind or 'event'} ({event_name})")
        if dispatch_args:
            extra_ctx_lines.append(f"- Dispatch Arguments: {dispatch_args}")
        if registered_at:
            extra_ctx_lines.append(f"- Callback Registered At: {registered_at}")
        if caller_site:
            extra_ctx_lines.append(f"- SFUI Caller Site: {caller_site}")
        if in_combat != "":
            extra_ctx_lines.append(f"- In Combat Lockdown: {in_combat}")
        if client_ver:
            extra_ctx_lines.append(f"- Client Version: {client_ver} (TOC {err.get('toc_version', '')})")
        if locals_dump:
            extra_ctx_lines.append(f"- Local Variables at Crash Frame:\n{locals_dump}")
        extra_ctx_block = ("\n".join(extra_ctx_lines) + "\n") if extra_ctx_lines else ""

        # Construct surgical task prompt for agy adhering strictly to .agent directives
        prompt = (
            f"Analyze and, ONLY if genuinely caused by a defect in addon 'sfui', fix this World of Warcraft Lua error recorded by BugJar:\n\n"
            f"- Error Message: {msg}\n"
            f"- Kind: {kind}\n"
            f"- Location: {loc}\n"
            f"{extra_ctx_block}"
            f"- Stack:\n{stack}\n\n"
            f"Mandatory Project Directives (from AGENTS.md and .agent/workflows/methods.md):\n"
            f"0. Root-Cause Attribution Guard (CRITICAL): First verify that this error originates in or is directly caused by a bug in the 'sfui' project.\n"
            f"   - If the error is caused by another third-party addon, a Blizzard UI bug, or ambient Midnight secret-value/taint noise where 'sfui' is not at fault, DO NOT modify any files and DO NOT delete or gut working 'sfui' features. Simply print 'SKIP_NOT_SFUI: <reason>' and exit immediately.\n"
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
            head_before = run_cmd(["git", "rev-parse", "HEAD"], check=False).stdout.strip()

            best_model = get_best_high_model()
            print(f"invoking agy agent runner ({best_model}) to dissect and patch...")
            res = subprocess.run(
                ["agy", "--model", best_model, "--effort", "high", "--print", prompt, "--dangerously-skip-permissions"],
                cwd=SFUI_DIR,
                capture_output=True,
                text=True,
                timeout=600
            )
            print("agy finished. returncode:", res.returncode)

            skipped_not_sfui = "SKIP_NOT_SFUI" in (res.stdout or "")
            if skipped_not_sfui:
                print("agent determined error is not caused by sfui; Reverting any scratch edits.")
                run_cmd(["git", "checkout", "--", "."], check=False)

            # Check if any git changes remain uncommitted or if commit was made
            diff_proc = run_cmd(["git", "status", "--porcelain"], check=False)
            if diff_proc.stdout.strip() and not skipped_not_sfui:
                # Guarantee release files are never modified by the auto-fixer
                run_cmd(["git", "checkout", "--", "sfui.toc", "CHANGELOG.md"], check=False)
                diff_after_clean = run_cmd(["git", "status", "--porcelain"], check=False)
                if diff_after_clean.stdout.strip():
                    # Verify syntax before committing
                    syntax_check = run_cmd(["bash", "-c", "find . -name '*.lua' -exec luac -p {} +"], check=False)
                    if syntax_check.returncode == 0:
                        run_cmd(["git", "add", "-A"])
                        run_cmd(["git", "commit", "-m", f"fix(bugjar): {msg[:60].lower()}"])
                        run_cmd(["git", "push", "origin", "main"], check=False)
                    else:
                        print("syntax check failed on unstaged changes! aborting commit.")
                        run_cmd(["git", "checkout", "--", "."], check=False)

            head_after = run_cmd(["git", "rev-parse", "HEAD"], check=False).stdout.strip()
            did_fix = bool(head_before and head_after and head_before != head_after)

            # Record resolved state (both fixed and verified non-sfui errors so we never re-run them)
            state["resolved"][fp] = {
                "message": msg,
                "kind": kind,
                "location": loc,
                "status": "fixed" if did_fix else "skipped_not_sfui",
                "resolved_at": int(time.time()),
                "time_str": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            }
            if did_fix:
                state["total_fixed"] = state.get("total_fixed", 0) + 1
                clean_msg = msg.replace("[Blocked]", "").strip()[:40].lower()
                state["last_fix"] = clean_msg
                state["last_fix_time"] = int(time.time())
                notify("SFUI Auto-Patcher", f"Fixed and pushed: {msg[:50]}")
            else:
                print("no sfui changes committed (marked resolved/ignored in bugjar state).")
            save_state(state)

        except subprocess.TimeoutExpired:
            print("agy run timed out after 600 seconds; cleaning up working tree.")
            run_cmd(["git", "checkout", "--", "."], check=False)
        except Exception as ex:
            print(f"error during auto-patch: {ex}")
            run_cmd(["git", "checkout", "--", "."], check=False)
        finally:
            if stash_created:
                print("restoring uncommitted working tree changes from stash...")
                run_cmd(["git", "stash", "pop"], check=False)

    save_state(state)
    print("all new errors processed.")

if __name__ == "__main__":
    main()
