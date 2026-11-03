#!/usr/bin/env python3
"""
SFUI Bonus Roll Chest Database Synchronizer (Retail)
Automatically discovers and synchronizes `CHEST_DATABASE` in `frames/gear/bonusroll.lua` from:
  1) Authoritative Blizzard DB2 tables via Wago Tools (`BonusRoll`, `JournalEncounter`, `JournalInstance`, `MapChallengeMode`)
  2) Wowhead Item Search & Nether Tooltip CDN (`https://www.wowhead.com/items/name:Voidcache`, `https://nether.wowhead.com/tooltip/item/<id>`)

Supports automatic triggering on Warcraft client / Wago build updates via `--on-update` and `--auto-commit`.

Usage:
    python3 scripts/sync-bonusroll.py [--on-update] [--major-only] [--auto-commit] [--dry-run] [--verbose]
"""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sync_core import (
    REPO_ROOT,
    extract_listview_data,
    fetch_url,
    write_lua_atomically,
)

TARGET_FILE = os.path.join(REPO_ROOT, "frames", "gear", "bonusroll.lua")
STATE_FILE = os.path.join(REPO_ROOT, ".agent", "bonusroll_sync_state.json")
WAGO_DB2_BASE = "https://wago.tools/db2"
WAGO_BUILDS_URL = "https://wago.tools/api/builds"
WOWHEAD_VOIDCACHE_SEARCH = "https://www.wowhead.com/items/name:Voidcache"
LOCAL_BUILD_INFO_PATHS = (
    os.path.expanduser("~/Games/World of Warcraft/.build.info"),
    os.path.expanduser("~/Games/World of Warcraft/_retail_/.build.info"),
    os.path.expanduser("~/Games/World of Warcraft 2/.build.info"),
)


def _norm_name(s: str) -> str:
    if not s:
        return ""
    s = re.sub(r"^the\s+", "", s.strip(), flags=re.IGNORECASE)
    return re.sub(r"[^a-z0-9]+", "", s.lower())


def _parse_version_tuple(ver_str: str) -> tuple[int, int, int, int]:
    """Parses '12.1.5.70688' -> (12, 1, 5, 70688)."""
    if not ver_str:
        return (0, 0, 0, 0)
    parts = [int(x) for x in re.findall(r"\d+", ver_str)]
    while len(parts) < 4:
        parts.append(0)
    return (parts[0], parts[1], parts[2], parts[3])


def get_current_wow_build() -> str:
    """
    Detects the latest Retail World of Warcraft version (e.g. '12.1.5.70688') from:
      1) Local Battle.net `.build.info` (for product `wow`)
      2) Wago Tools Builds API (`https://wago.tools/api/builds`)
    Returns the highest detected version string.
    """
    best_ver = ""
    best_tuple = (0, 0, 0, 0)

    # 1. Check local .build.info files
    for path in LOCAL_BUILD_INFO_PATHS:
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                lines = [ln.strip() for ln in f if ln.strip()]
            if len(lines) < 2:
                continue
            headers = [h.split("!")[0].strip() for h in lines[0].split("|")]
            ver_idx = headers.index("Version") if "Version" in headers else -1
            prod_idx = headers.index("Product") if "Product" in headers else -1
            if ver_idx == -1:
                continue
            for row in lines[1:]:
                cols = row.split("|")
                if prod_idx != -1 and prod_idx < len(cols) and cols[prod_idx].strip() != "wow":
                    continue
                if ver_idx < len(cols):
                    v = cols[ver_idx].strip()
                    vt = _parse_version_tuple(v)
                    if vt > best_tuple:
                        best_tuple = vt
                        best_ver = v
        except Exception:
            pass

    # 2. Check Wago Tools API
    raw = fetch_url(WAGO_BUILDS_URL, timeout=8, max_retries=1, allow_waf=False)
    if raw:
        try:
            data = json.loads(raw)
            wow_list = data.get("wow") or []
            if isinstance(wow_list, list) and wow_list:
                v = (wow_list[0].get("version") or "").strip()
                vt = _parse_version_tuple(v)
                if vt > best_tuple:
                    best_tuple = vt
                    best_ver = v
        except Exception:
            pass

    return best_ver


def load_sync_state() -> dict:
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_sync_state(state: dict):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def fetch_wago_csv(table_name: str) -> list[dict]:
    url = f"{WAGO_DB2_BASE}/{table_name}/csv"
    raw = fetch_url(url, timeout=12, max_retries=2, allow_waf=False)
    if not raw:
        return []
    return list(csv.DictReader(io.StringIO(raw)))


def discover_chests_from_db2_and_wowhead(verbose: bool = False) -> tuple[dict, dict]:
    """
    Returns (dungeon_chests, raid_chests):
      dungeon_chests[cache_id] = {"challengeModeId": int, "instanceID": int, "name": str}
      raid_chests[cache_id]    = {"bossId": int, "instanceID": int, "name": str}
    """
    bonus_rows = fetch_wago_csv("BonusRoll")
    enc_rows = fetch_wago_csv("JournalEncounter")
    inst_rows = fetch_wago_csv("JournalInstance")
    cm_rows = fetch_wago_csv("MapChallengeMode")

    encounters = {}
    encounters_by_norm = {}
    for r in enc_rows:
        eid = int(r.get("ID") or 0)
        if eid > 0:
            encounters[eid] = r
            nm = _norm_name(r.get("Name_lang", ""))
            if nm:
                encounters_by_norm[nm] = r

    instances = {}
    instances_by_norm = {}
    for r in inst_rows:
        iid = int(r.get("ID") or 0)
        if iid > 0:
            instances[iid] = r
            nm = _norm_name(r.get("Name_lang", ""))
            if nm:
                prev = instances_by_norm.get(nm)
                if not prev or iid > int(prev.get("ID") or 0):
                    instances_by_norm[nm] = r

    cm_by_map = {}
    cm_by_norm = {}
    for r in cm_rows:
        cm_id = int(r.get("ID") or 0)
        map_id = int(r.get("MapID") or 0)
        if cm_id > 0 and map_id > 0:
            if map_id not in cm_by_map:
                cm_by_map[map_id] = cm_id
            nm = _norm_name(r.get("Name_lang", ""))
            if nm:
                cm_by_norm[nm] = (cm_id, map_id, r.get("Name_lang", ""))

    dungeon_chests = {}
    raid_chests = {}

    # 1. Primary authoritative source: Blizzard's BonusRoll.db2
    known_core_cols = {"ID", "CurrencyTypesID", "CurrencyCost", "JournalEncounterID", "JournalInstanceID"}
    for r in bonus_rows:
        cache_id = 0
        for col, val in r.items():
            if col not in known_core_cols and val and str(val).isdigit():
                v = int(val)
                if v >= 100000:
                    cache_id = v
                    break
        if cache_id <= 0:
            continue

        enc_id = int(r.get("JournalEncounterID") or 0)
        inst_id = int(r.get("JournalInstanceID") or 0)

        if enc_id > 0:
            enc = encounters.get(enc_id, {})
            if inst_id <= 0:
                inst_id = int(enc.get("JournalInstanceID") or 0)
            name = enc.get("Name_lang") or f"Boss {enc_id}"
            raid_chests[cache_id] = {
                "bossId": enc_id,
                "instanceID": inst_id,
                "name": name,
            }
        elif inst_id > 0:
            inst = instances.get(inst_id, {})
            map_id = int(inst.get("MapID") or 0)
            cm_id = cm_by_map.get(map_id)
            name = inst.get("Name_lang") or f"Dungeon {inst_id}"
            if not cm_id:
                nm = _norm_name(name)
                if nm in cm_by_norm:
                    cm_id = cm_by_norm[nm][0]
            dungeon_chests[cache_id] = {
                "challengeModeId": cm_id,
                "instanceID": inst_id,
                "name": name,
            }

    # 2. Secondary discovery: Wowhead Voidcache item search (for early PTR/season items not yet in BonusRoll.db2)
    wh_html = fetch_url(WOWHEAD_VOIDCACHE_SEARCH, timeout=12)
    if wh_html:
        _, wh_items = extract_listview_data(wh_html, "items")
        for it in wh_items:
            cid = int(it.get("id") or 0)
            raw_name = (it.get("name") or "").strip()
            if cid <= 0 or cid in raid_chests or cid in dungeon_chests:
                continue
            if ":" not in raw_name:
                continue
            target_label = raw_name.split(":", 1)[1].strip()
            target_norm = _norm_name(target_label)
            if not target_norm or target_norm in ("delverstrove", "prey"):
                continue

            if target_norm in encounters_by_norm:
                enc = encounters_by_norm[target_norm]
                eid = int(enc["ID"])
                iid = int(enc.get("JournalInstanceID") or 0)
                raid_chests[cid] = {
                    "bossId": eid,
                    "instanceID": iid,
                    "name": enc.get("Name_lang") or target_label,
                }
                if verbose:
                    print(f"  [Wowhead] Matched raid chest {cid} -> bossId={eid}, instanceID={iid} ({target_label})")
            elif target_norm in cm_by_norm or target_norm in instances_by_norm:
                cm_id = cm_by_norm[target_norm][0] if target_norm in cm_by_norm else None
                inst = instances_by_norm.get(target_norm)
                iid = int(inst["ID"]) if inst else 0
                dungeon_chests[cid] = {
                    "challengeModeId": cm_id,
                    "instanceID": iid,
                    "name": (inst and inst.get("Name_lang")) or target_label,
                }
                if verbose:
                    print(f"  [Wowhead] Matched dungeon chest {cid} -> challengeModeId={cm_id}, instanceID={iid} ({target_label})")
            else:
                # Token-overlap fallback for reordered/renamed bosses (e.g. 'Soulcoiler Nek'zali' vs 'Nek'zali the Soulcoiler')
                stopwords = {"the", "of", "and", "in", "on", "at", "to", "for"}
                t_tokens = {w for w in re.findall(r"[a-z0-9]+", target_label.lower()) if len(w) >= 4 and w not in stopwords}
                best_enc = None
                best_score = 0
                tied = False
                for eid, enc in encounters.items():
                    if eid < 2700:
                        continue
                    e_tokens = {w for w in re.findall(r"[a-z0-9]+", (enc.get("Name_lang") or "").lower()) if len(w) >= 4 and w not in stopwords}
                    score = len(t_tokens & e_tokens)
                    if score > best_score:
                        best_score = score
                        best_enc = enc
                        tied = False
                    elif score > 0 and score == best_score:
                        tied = True
                if best_enc and best_score > 0 and not tied:
                    eid = int(best_enc["ID"])
                    iid = int(best_enc.get("JournalInstanceID") or 0)
                    raid_chests[cid] = {
                        "bossId": eid,
                        "instanceID": iid,
                        "name": best_enc.get("Name_lang") or target_label,
                    }
                    if verbose:
                        print(f"  [Wowhead Token] Matched raid chest {cid} -> bossId={eid}, instanceID={iid} ({target_label})")

    return dungeon_chests, raid_chests


def _auto_commit_and_push(build_ver: str):
    """Commits and pushes bonusroll.lua if it is the only dirty file and passes luacheck."""
    rel_target = os.path.relpath(TARGET_FILE, REPO_ROOT)
    st = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    dirty_lines = [ln.strip() for ln in st.stdout.splitlines() if ln.strip()]
    if len(dirty_lines) != 1 or not dirty_lines[0].endswith(rel_target):
        print("Working tree has other changes; skipping auto-commit.")
        return

    lc = subprocess.run(["luacheck", rel_target], cwd=REPO_ROOT, capture_output=True, text=True)
    if lc.returncode != 0:
        print(f"luacheck failed on {rel_target}; skipping auto-commit:\n{lc.stdout}", file=sys.stderr)
        return

    msg = f"chore(bonusroll): sync chest database for wow {build_ver or 'update'}".lower()
    subprocess.run(["git", "add", rel_target], cwd=REPO_ROOT, check=True)
    subprocess.run(["git", "commit", "-m", msg], cwd=REPO_ROOT, check=True)
    subprocess.run(["git", "push", "origin", "main"], cwd=REPO_ROOT, check=False)
    print(f"Auto-committed and pushed: {msg}")


def sync_bonusroll(
    dry_run: bool = False,
    verbose: bool = False,
    on_update: bool = False,
    major_only: bool = False,
    auto_commit: bool = False,
) -> bool:
    if not os.path.exists(TARGET_FILE):
        print(f"Error: {TARGET_FILE} not found.", file=sys.stderr)
        return False

    current_build = get_current_wow_build()
    cur_tuple = _parse_version_tuple(current_build)
    cur_patch_key = f"{cur_tuple[0]}.{cur_tuple[1]}.{cur_tuple[2]}" if cur_tuple[0] > 0 else ""

    state = load_sync_state()
    last_build = state.get("last_build", "")
    last_patch_key = state.get("last_patch_key", "")

    if on_update and current_build:
        if major_only and cur_patch_key and cur_patch_key == last_patch_key:
            if verbose:
                print(f"WoW patch version unchanged ({cur_patch_key}); skipping bonusroll sync.")
            return False
        if not major_only and current_build == last_build:
            if verbose:
                print(f"WoW build unchanged ({current_build}); skipping bonusroll sync.")
            return False
        print(f"Detected Warcraft update ({last_build or 'none'} -> {current_build}); running bonusroll chest sync...")

    with open(TARGET_FILE, "r", encoding="utf-8") as f:
        lua_text = f.read()

    # Parse existing CHEST_DATABASE entries so none are ever lost if offline
    block_match = re.search(
        r"(local CHEST_DATABASE = \{\n)(.*?)(\n\})",
        lua_text,
        re.DOTALL,
    )
    if not block_match:
        print("Error: Could not locate `local CHEST_DATABASE = { ... }` in bonusroll.lua", file=sys.stderr)
        return False

    existing_dungeons = {}
    existing_raids = {}
    for line in block_match.group(2).splitlines():
        m_d = re.search(
            r"\[(\d+)\]\s*=\s*\{\s*challengeModeId\s*=\s*(\d+),\s*instanceID\s*=\s*(\d+)\s*\},\s*--\s*(.+)",
            line,
        )
        if m_d:
            existing_dungeons[int(m_d.group(1))] = {
                "challengeModeId": int(m_d.group(2)),
                "instanceID": int(m_d.group(3)),
                "name": m_d.group(4).strip(),
            }
            continue
        m_r = re.search(
            r"\[(\d+)\]\s*=\s*\{\s*bossId\s*=\s*(\d+),\s*instanceID\s*=\s*(\d+)\s*\},\s*--\s*(.+)",
            line,
        )
        if m_r:
            existing_raids[int(m_r.group(1))] = {
                "bossId": int(m_r.group(2)),
                "instanceID": int(m_r.group(3)),
                "name": m_r.group(4).strip(),
            }

    dungeon_chests, raid_chests = discover_chests_from_db2_and_wowhead(verbose=verbose)
    if not dungeon_chests and not raid_chests:
        print("Warning: Could not reach Wago DB2 or Wowhead; keeping existing CHEST_DATABASE.")
        return False

    merged_dungeons = dict(existing_dungeons)
    for cid, info in dungeon_chests.items():
        prev = merged_dungeons.get(cid, {})
        merged_dungeons[cid] = {
            "challengeModeId": info.get("challengeModeId") or prev.get("challengeModeId"),
            "instanceID": info.get("instanceID") or prev.get("instanceID"),
            "name": info.get("name") or prev.get("name") or f"Dungeon {cid}",
        }

    merged_raids = dict(existing_raids)
    for cid, info in raid_chests.items():
        prev = merged_raids.get(cid, {})
        merged_raids[cid] = {
            "bossId": info.get("bossId") or prev.get("bossId"),
            "instanceID": info.get("instanceID") or prev.get("instanceID"),
            "name": info.get("name") or prev.get("name") or f"Boss {cid}",
        }

    lines = ["    -- Dungeons (challengeModeId & instanceID)"]
    for cid in sorted(merged_dungeons.keys()):
        d = merged_dungeons[cid]
        cm_id = d.get("challengeModeId")
        inst_id = d.get("instanceID")
        name = d.get("name", "")
        if cm_id and inst_id:
            lines.append(f"    [{cid}] = {{ challengeModeId = {cm_id}, instanceID = {inst_id} }}, -- {name}")
        elif inst_id:
            lines.append(f"    [{cid}] = {{ instanceID = {inst_id} }}, -- {name}")

    lines.append("")
    lines.append("    -- Raid Bosses (encounterID / bossId & instanceID)")
    for cid in sorted(merged_raids.keys()):
        r = merged_raids[cid]
        boss_id = r.get("bossId")
        inst_id = r.get("instanceID")
        name = r.get("name", "")
        if boss_id and inst_id:
            lines.append(f"    [{cid}] = {{ bossId = {boss_id}, instanceID = {inst_id} }}, -- {name}")
        elif boss_id:
            lines.append(f"    [{cid}] = {{ bossId = {boss_id} }}, -- {name}")

    new_block = block_match.group(1) + "\n".join(lines) + block_match.group(3)
    new_lua = lua_text[:block_match.start()] + new_block + lua_text[block_match.end():]

    print(
        f"Synchronized {len(merged_dungeons)} dungeon chests and {len(merged_raids)} raid/world boss chests "
        f"(build: {current_build or 'unknown'})."
    )

    if dry_run:
        print("[Dry Run] Skipping file write.")
        return False

    changed = write_lua_atomically(TARGET_FILE, new_lua)
    if current_build:
        save_sync_state({
            "last_build": current_build,
            "last_patch_key": cur_patch_key,
            "last_sync_ts": int(time.time()),
            "dungeon_count": len(merged_dungeons),
            "raid_count": len(merged_raids),
        })

    if changed:
        print(f"Updated {os.path.relpath(TARGET_FILE, REPO_ROOT)} successfully.")
        if auto_commit:
            _auto_commit_and_push(current_build)
    else:
        print(f"{os.path.relpath(TARGET_FILE, REPO_ROOT)} is already up to date.")
    return changed


def main():
    parser = argparse.ArgumentParser(description="Synchronize Retail Bonus Roll CHEST_DATABASE from Wago DB2 & Wowhead.")
    parser.add_argument("--on-update", action="store_true", help="Only run if a new WoW build/patch is detected.")
    parser.add_argument("--major-only", action="store_true", help="With --on-update, only trigger when major.minor.patch changes.")
    parser.add_argument("--auto-commit", action="store_true", help="Automatically commit and push if bonusroll.lua changed.")
    parser.add_argument("--dry-run", action="store_true", help="Preview without modifying bonusroll.lua.")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose logging.")
    args = parser.parse_args()
    sync_bonusroll(
        dry_run=args.dry_run,
        verbose=args.verbose,
        on_update=args.on_update,
        major_only=args.major_only,
        auto_commit=args.auto_commit,
    )


if __name__ == "__main__":
    main()
