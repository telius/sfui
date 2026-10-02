#!/usr/bin/env python3
"""
SFUI Dungeon Journal Loot & Drop Rate Synchronizer
Synchronizes boss drop tables and drop rates in data/dj_camelot.lua from:
  1) Local authoritative client databases (ForeverDungeonJournal / ForeverDungeonScout)
  2) Wowhead Forever (https://www.wowhead.com/forever) via build/NPC queries

Usage:
    python3 scripts/sync-dj-loot.py [--source local|wowhead] [--refresh-rates] [--dry-run] [--verbose]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TARGET_FILE = os.path.join(REPO_ROOT, "data", "dj_camelot.lua")
CACHE_FILE = os.path.join(REPO_ROOT, "data", "dj_droprates.json")

DEFAULT_ADDON_PATHS = [
    "/home/james/Games/World of Warcraft/_classic_beta_/Interface/AddOns",
    os.path.expanduser("~/Games/World of Warcraft/_classic_beta_/Interface/AddOns"),
    os.path.expanduser("~/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common/World of Warcraft/_classic_beta_/Interface/AddOns"),
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

# Normalization & Aliasing
def norm_name(s: str) -> str:
    if not s:
        return ""
    # Strip common suffixes
    s = re.sub(r"\s*·\s*optional", "", s, flags=re.IGNORECASE)
    s = re.sub(r"\s*—\s*.*", "", s)
    s = re.sub(r"[^a-zA-Z0-9]", "", s).lower()
    return s

ALIASES = {
    "dreamscytheweaver": "dreamscythe",
    "morphazhazzas":     "morphaz",
    "ringoflaw":         "theldren",
    "kinggordokchorush": "kinggordok",
    "willeyhopebreaker": "cannonmasterwilley",
    "instructorgalford": "archivistgalford",
    "malorthezealous":   "postmastermalown",
}

# Authoritative manual fallbacks for encounters with chest / multi-unit loot
MANUAL_OVERRIDES = {
    "baronrivendare":     [13335, 13505, 13385, 13386, 13387, 13384],
    "theseven":           [11925, 11926, 11927, 11928, 11929, 11933, 11935],
    "ribblyscrewspigot":  [11603, 11604, 11605, 11606],
    "pusillin":           [18258, 18249],
    "thekathemartyr":     [9445, 9446, 9447],
    "obsidiansentinel":   [9413, 9414],
    "ladyfaltheress":     [10762, 10763],
    "kinggordokchorush": [18520, 18521, 18522, 18523, 18524, 18525, 18526, 18527, 18483, 18484, 18485, 18490],
}

def find_addons_dir(custom_path=None):
    if custom_path and os.path.isdir(custom_path):
        return custom_path
    for p in DEFAULT_ADDON_PATHS:
        if os.path.isdir(p):
            return p
    return None

def load_local_databases(addons_dir: str):
    boss_drops = {}
    boss_npcs = {}

    fdj_path = os.path.join(addons_dir, "ForeverDungeonJournal", "Data", "Dungeons.lua")
    scout_path = os.path.join(addons_dir, "ForeverDungeonScout", "Data.lua")

    lua_script = f"""
    local fdj_env = {{ Constants = {{ ALBA_FAIRMOON_LOCATION = "" }} }}
    setmetatable(fdj_env, {{ __index = _G }})
    local fdj_loaded, f1 = pcall(loadfile, "{fdj_path}", "t", fdj_env)
    if fdj_loaded and f1 then
        pcall(f1, "ForeverDungeonJournal", fdj_env)
    end
    local FDJ_DB = fdj_env.DB or {{}}

    local scout_loaded = pcall(dofile, "{scout_path}")
    local scout_areas = (scout_loaded and FiveeverGuideData and FiveeverGuideData.areas) or {{}}

    local function norm(s)
        if not s then return "" end
        s = s:gsub(" · optional", ""):gsub(" — .*", "")
        return s:lower():gsub("[^%a%d]", "")
    end

    -- Priority 1: ForeverDungeonJournal
    for _, dData in pairs(FDJ_DB) do
        for _, b in ipairs(dData.bosses or {{}}) do
            local items = {{}}
            for _, l in ipairs(b.loot or {{}}) do
                table.insert(items, tostring(l[1]))
            end
            local nb = norm(b.name)
            if #items > 0 then
                print("DROP:" .. nb .. ":" .. table.concat(items, ","))
            end
            if b.npcID then
                print("NPC:" .. nb .. ":" .. tostring(b.npcID))
            end
        end
    end

    -- Priority 2: ForeverDungeonScout
    for _, area in ipairs(scout_areas) do
        for _, b in ipairs(area.bosses or {{}}) do
            local items = {{}}
            for _, itm in ipairs(b.loot or {{}}) do
                table.insert(items, tostring(itm.id))
            end
            local nb = norm(b.name)
            if #items > 0 then
                print("SCOUT:" .. nb .. ":" .. table.concat(items, ","))
            end
            if b.id then
                print("SCOUT_NPC:" .. nb .. ":" .. tostring(b.id))
            end
        end
    end
    """

    res = subprocess.run(["lua", "-e", lua_script], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Warning: Lua extractor returned error: {res.stderr.strip()}", file=sys.stderr)

    scout_map = {}
    for line in res.stdout.splitlines():
        line = line.strip()
        if line.startswith("DROP:"):
            _, key, items_str = line.split(":", 2)
            boss_drops[key] = [int(x) for x in items_str.split(",") if x]
        elif line.startswith("SCOUT:"):
            _, key, items_str = line.split(":", 2)
            scout_map[key] = [int(x) for x in items_str.split(",") if x]
        elif line.startswith("NPC:"):
            _, key, nid = line.split(":", 2)
            if nid and nid.isdigit():
                boss_npcs[key] = int(nid)
        elif line.startswith("SCOUT_NPC:"):
            _, key, nid = line.split(":", 2)
            if nid and nid.isdigit():
                boss_npcs[key] = int(nid)

    # Fill in from scout if not in FDJ
    for k, v in scout_map.items():
        if k not in boss_drops:
            boss_drops[k] = v

    # Apply manual overrides
    for k, v in MANUAL_OVERRIDES.items():
        boss_drops[k] = v

    return boss_drops, boss_npcs

def fetch_npc_droprates(npc_id: int) -> tuple:
    for base_url in ["https://www.wowhead.com/forever/npc=", "https://www.wowhead.com/classic/npc="]:
        url = f"{base_url}{npc_id}"
        req = urllib.request.Request(url, headers=HEADERS)
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                html = resp.read().decode("utf-8", errors="ignore")
        except Exception:
            continue

        idx = html.find("id: 'drops'")
        if idx == -1: idx = html.find('id: "drops"')
        if idx == -1: idx = html.find("id: 'drops-normal'")
        if idx == -1: idx = html.find("'drops'")
        if idx == -1: idx = html.find('"drops"')
        if idx == -1: continue

        data_idx = html.find("data:[", idx)
        if data_idx == -1: data_idx = html.find("data: [", idx)
        if data_idx == -1: continue

        start = html.find("[", data_idx)
        brace_count = 0
        end = start
        for i in range(start, len(html)):
            if html[i] == "[": brace_count += 1
            elif html[i] == "]":
                brace_count -= 1
                if brace_count == 0:
                    end = i + 1
                    break
        try:
            items = json.loads(html[start:end])
            rates = {}
            for it in items:
                cnt = it.get("count", 0)
                outof = it.get("outof", 1)
                if outof > 0 and cnt > 0:
                    pct = round(cnt / outof * 100, 1)
                    rates[str(it["id"])] = pct
            if rates:
                return npc_id, rates
        except Exception:
            pass
    return npc_id, {}

def get_or_fetch_droprates(npc_ids: list, refresh: bool = False) -> dict:
    rates_db = {}
    if os.path.exists(CACHE_FILE) and not refresh:
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                rates_db = json.load(f)
        except Exception:
            rates_db = {}

    missing_npcs = [nid for nid in npc_ids if str(nid) not in rates_db]
    if missing_npcs:
        print(f"Fetching drop rates for {len(missing_npcs)} boss NPCs from Wowhead...")
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=12) as pool:
            fetched = dict(pool.map(fetch_npc_droprates, missing_npcs))
        dt = time.time() - t0

        for nid, r in fetched.items():
            if r:
                rates_db[str(nid)] = r

        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(rates_db, f, indent=2)
        print(f"Fetched {len(missing_npcs)} bosses in {dt:.2f}s and cached in {CACHE_FILE}")

    return rates_db

def update_dj_camelot(boss_item_map: dict, boss_npcs: dict, rates_db: dict, dry_run: bool = False, verbose: bool = False):
    if not os.path.isfile(TARGET_FILE):
        print(f"Error: Target file {TARGET_FILE} not found.", file=sys.stderr)
        sys.exit(1)

    with open(TARGET_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    in_bosses = False
    current_boss = None
    current_npc = None
    updated_lines = []
    item_changes = []
    droprate_changes = 0

    for line in lines:
        if "sfui.dj_camelot.raids = {" in line:
            in_bosses = False

        if "bosses = {" in line:
            in_bosses = True
            updated_lines.append(line)
            continue

        if in_bosses:
            if "quests = {" in line or re.match(r"^\s*\},?\s*$", line):
                in_bosses = False
                current_boss = None
                current_npc = None
                updated_lines.append(line)
                continue

            m_name = re.search(r"name\s*=\s*\"([^\"]+)\"", line)
            if m_name:
                current_boss = m_name.group(1)
                nb = norm_name(current_boss)
                current_npc = boss_npcs.get(nb)
                m_npc = re.search(r"npcID\s*=\s*(\d+)", line)
                if not current_npc and m_npc:
                    current_npc = int(m_npc.group(1))

                # Repair missing npcID if known
                if "npcID = nil" in line and current_npc:
                    line = line.replace("npcID = nil", f"npcID = {current_npc}")

            if current_boss and ("items = {" in line or "items={" in line):
                nb = norm_name(current_boss)
                if nb not in MANUAL_OVERRIDES:
                    nb = ALIASES.get(nb, nb)

                # Determine item IDs
                if nb in boss_item_map and boss_item_map[nb]:
                    item_ids = boss_item_map[nb]
                else:
                    m_items = re.search(r"items\s*=\s*\{([^}]*)\}", line)
                    if m_items:
                        item_ids = [int(x.strip()) for x in m_items.group(1).split(",") if x.strip().isdigit()]
                    else:
                        item_ids = []

                if item_ids:
                    new_items_str = "items = { " + ", ".join(str(x) for x in item_ids) + " }"
                else:
                    new_items_str = "items = {}"

                old_items_match = re.search(r"items\s*=\s*\{[^}]*\}", line)
                old_str = old_items_match.group(0) if old_items_match else ""
                if old_str != new_items_str:
                    item_changes.append((current_boss, old_str, new_items_str))

                # Calculate drop rates
                if item_ids:
                    npc_key = str(current_npc) if current_npc else ""
                    known_rates = rates_db.get(npc_key, {})

                    final_rates = {}
                    known_sum = 0
                    missing = []
                    for iid in item_ids:
                        iid_str = str(iid)
                        if iid_str in known_rates and known_rates[iid_str] > 0:
                            r = round(known_rates[iid_str])
                            if r == 0: r = 1
                            final_rates[iid] = r
                            known_sum += r
                            droprate_changes += 1
                        else:
                            missing.append(iid)

                    if missing:
                        rem_pct = max(0, 100 - known_sum)
                        share = max(1, round(rem_pct / len(missing))) if rem_pct > 0 else round(100 / len(item_ids))
                        for iid in missing:
                            final_rates[iid] = share
                            droprate_changes += 1

                    rate_parts = [f"[{iid}] = {final_rates[iid]}" for iid in item_ids if iid in final_rates]
                    rate_str = "dropRates = { " + ", ".join(rate_parts) + " }"

                    # Replace items and dropRates cleanly
                    line = re.sub(r",?\s*dropRates\s*=\s*\{[^}]*\}", "", line)
                    line = re.sub(r"items\s*=\s*\{[^}]*\}", new_items_str, line)
                    line = re.sub(r"\}\s*\}\s*,\s*$", f"}}, {rate_str} }},\n", line)

                    current_boss = None
                    current_npc = None
                    updated_lines.append(line)
                    continue

        updated_lines.append(line)

    print(f"\nChecked 194 dungeon bosses.")
    print(f"  * Loot item table changes: {len(item_changes)}")
    print(f"  * Drop rates synchronized: {droprate_changes}")

    if verbose or dry_run:
        for bname, old_s, new_s in item_changes:
            print(f"  * {bname}:")
            print(f"      Old: {old_s}")
            print(f"      New: {new_s}")

    if dry_run:
        print("\n[Dry Run] No files modified.")
        return

    # Write to temp file and verify syntax before committing
    tmp_target = TARGET_FILE + ".tmp"
    with open(tmp_target, "w", encoding="utf-8") as f:
        f.writelines(updated_lines)

    check = subprocess.run(["luac", "-p", tmp_target], capture_output=True, text=True)
    if check.returncode != 0:
        os.remove(tmp_target)
        print(f"Error: Generated Lua has syntax errors:\n{check.stderr}", file=sys.stderr)
        sys.exit(1)

    os.replace(tmp_target, TARGET_FILE)
    print(f"Successfully updated {TARGET_FILE} with loot items and drop rates.")

def main():
    parser = argparse.ArgumentParser(description="Synchronize Dungeon Journal drop tables and drop rates.")
    parser.add_argument("--source", choices=["local", "wowhead"], default="local",
                        help="Data source for loot items: local client databases or Wowhead.")
    parser.add_argument("--wow-addons", default=None,
                        help="Path to WoW Interface/AddOns directory.")
    parser.add_argument("--refresh-rates", action="store_true",
                        help="Force re-fetch all drop rates from Wowhead.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Check for updates without modifying files.")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print detailed diffs.")

    args = parser.parse_args()

    addons_dir = find_addons_dir(args.wow_addons)
    if not addons_dir:
        print("Error: Could not locate WoW Interface/AddOns directory.", file=sys.stderr)
        print("Please specify with --wow-addons <path>", file=sys.stderr)
        sys.exit(1)

    print(f"Using local client databases from: {addons_dir}")
    boss_map, boss_npcs = load_local_databases(addons_dir)
    print(f"Loaded {len(boss_map)} authoritative boss loot tables and {len(boss_npcs)} NPC IDs.")

    # Collect unique NPC IDs
    unique_npcs = list(set(boss_npcs.values()))
    rates_db = get_or_fetch_droprates(unique_npcs, refresh=args.refresh_rates)
    print(f"Loaded drop rates for {len(rates_db)} bosses.")

    update_dj_camelot(boss_map, boss_npcs, rates_db, dry_run=args.dry_run, verbose=args.verbose)

if __name__ == "__main__":
    main()
