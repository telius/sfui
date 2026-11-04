#!/usr/bin/env python3
"""
SFUI Dungeon Journal Loot, Drop Rate & Quest Synchronizer
Self-contained tool to synchronize boss drop tables, drop rates, and quest rewards in data/dj_camelot.lua from:
  1) Local authoritative repository data (data/dj_camelot.lua, data/dj_droprates.json, data/dj_questrewards.json)
  2) Wowhead Forever Official Dungeon Quest Guide:
     https://www.wowhead.com/forever/guide/dungeons/every-dungeon-quest-location
  3) Wowhead Forever online endpoints (https://www.wowhead.com/forever) via NPC & Quest queries

Usage:
    python3 scripts/sync-dj-loot.py [--refresh-rates] [--refresh-quests] [--check-guide] [--dry-run] [--verbose]
"""

import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from sync_core import (
    DATA_DIR,
    REPO_ROOT,
    extract_listview_data,
    fetch_url,
    load_forever_zones,
    write_lua_atomically,
)

TARGET_FILE = os.path.join(DATA_DIR, "dj_camelot.lua")
CACHE_FILE = os.path.join(DATA_DIR, "dj_droprates.json")
QUEST_CACHE_FILE = os.path.join(DATA_DIR, "dj_questrewards.json")
WOWHEAD_QUESTS_CACHE = os.path.join(DATA_DIR, "dj_wowhead_quests.json")
WOWHEAD_GUIDE_URL = "https://www.wowhead.com/forever/guide/dungeons/every-dungeon-quest-location"

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

# Authoritative item rewards for keys / attunements / special quest turn-ins
KEY_QUEST_REWARDS = {
    4742: [12344],  # Seal of Ascension (Key to UBRS)
    4875: [18400],  # For The Horde! (Key to Onyxia's Lair - Horde)
    4974: [18399],  # Drakefire Amulet (Key to Onyxia's Lair - Alliance)
    7443: [18249],  # Crescent Key (Dire Maul)
    7044: [17191],  # Scepter of Celebras (Maraudon)
    6821: [17333],  # Aqual Quintessence (Molten Core)
    2945: [9328],   # Clean Grime-Encrusted Ring (Gnomeregan)
}

def load_base_data_from_lua(lua_path: str) -> tuple:
    """
    Extracts boss definitions, NPC IDs, existing loot tables, and quest IDs
    directly from data/dj_camelot.lua. SFUI does not rely on third-party addons.
    """
    boss_items = {}
    boss_npcs = {}
    all_qids = []

    with open(lua_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    for line in lines:
        m_bname = re.search(r'name\s*=\s*"([^"]+)"', line)
        m_npc = re.search(r'npcID\s*=\s*(\d+)', line)
        m_items = re.search(r'items\s*=\s*\{([^}]*)\}', line)

        if m_bname and m_npc:
            nb = norm_name(m_bname.group(1))
            boss_npcs[nb] = int(m_npc.group(1))

        if m_bname and m_items:
            nb = norm_name(m_bname.group(1))
            raw = m_items.group(1)
            itms = [int(x.strip()) for x in raw.split(",") if x.strip().isdigit()]
            boss_items[nb] = itms

        m_qid = re.search(r"^\s*\{\s*id\s*=\s*(\d+)", line)
        if m_qid:
            all_qids.append(int(m_qid.group(1)))

    # Apply manual overrides for chest / multi-unit encounters
    for k, v in MANUAL_OVERRIDES.items():
        boss_items[k] = v

    unique_qids = sorted(list(set(all_qids)))
    return boss_items, boss_npcs, unique_qids

def fetch_and_parse_wowhead_guide() -> dict:
    """
    Fetches and parses the authoritative Wowhead Forever guide:
    https://www.wowhead.com/forever/guide/dungeons/every-dungeon-quest-location
    Extracts all dungeon quest metadata, quest givers, coordinates, and prerequisite chain starters.
    """
    html = fetch_url(WOWHEAD_GUIDE_URL, timeout=12)
    if not html:
        print(f"Warning: Failed to fetch Wowhead guide from {WOWHEAD_GUIDE_URL}", file=sys.stderr)
        return {}

    # Extract names from WH.Gatherer.addData
    m_quests = re.search(r"WH\.Gatherer\.addData\(5,\s*16,\s*(\{.*?\})\);", html)
    quest_names = {int(k): v.get("name_enus", "") for k, v in json.loads(m_quests.group(1)).items()} if m_quests else {}

    m_npcs = re.search(r"WH\.Gatherer\.addData\(1,\s*16,\s*(\{.*?\})\);", html)
    npc_names = {int(k): v.get("name_enus", "") for k, v in json.loads(m_npcs.group(1)).items()} if m_npcs else {}

    sections = re.split(r"\[h2 type=bar toc=\\?\"([^\"]+?)\\?\"\]", html)
    guide_quests = {}

    for i in range(1, len(sections), 2):
        dungeon_name = sections[i].replace("\\", "")
        sec_content = sections[i + 1]

        rows = [r for r in re.findall(r"\[tr\](.*?)\[\\?/tr\]", sec_content, re.DOTALL) if "[quest=" in r]
        for r in rows:
            q_m = re.search(r"\[quest=(\d+)\]", r)
            if not q_m:
                continue
            qid = int(q_m.group(1))

            lvl_m = re.search(r"\[td align=center\](\d+)\s*\[\\?/td\]", r)
            lvl = int(lvl_m.group(1)) if lvl_m else 0

            side = "Both"
            if "side_horde" in r:
                side = "Horde"
            elif "side_alliance" in r:
                side = "Alliance"

            is_pre = "Pre" in r
            is_drop = "Drop" in r
            is_shareable = "fa-check" in r

            npc_m = re.search(r"\[npc=(\d+)\]", r)
            nid = int(npc_m.group(1)) if npc_m else None

            way_m = re.search(r"/way\s+([\d.]+)\s+([\d.]+)", r)
            coords = None
            if way_m:
                try:
                    coords = [float(way_m.group(1).rstrip(".")), float(way_m.group(2).rstrip("."))]
                except Exception:
                    pass

            loc_m = re.search(r"\[td\]\[b\]([^[]+)\[\\?/b\](?:,\s*([^-\[\n]+))?", r)
            zone = loc_m.group(1).strip() if loc_m else ""
            subzone = loc_m.group(2).strip() if (loc_m and loc_m.group(2)) else ""

            ptext = ""
            p_match = re.search(r"\[i\](.*?)\[\\?/i\]", r, re.DOTALL)
            if p_match:
                ptext = re.sub(r"\[/?.*?\]", "", p_match.group(1)).strip().replace("\\r", "").replace("\\n", " ")

            starter_qid = None
            starter_m = re.search(r"(?:starting with|Requires|from|after)\s*\[quest=(\d+)\]", r, re.IGNORECASE)
            if starter_m:
                starter_qid = int(starter_m.group(1))

            guide_quests[str(qid)] = {
                "qid": qid,
                "name": quest_names.get(qid, ""),
                "dungeon": dungeon_name,
                "level": lvl,
                "side": side,
                "is_pre": is_pre,
                "is_drop": is_drop,
                "is_shareable": is_shareable,
                "npc_id": nid,
                "npc_name": npc_names.get(nid, "") if nid else "",
                "coords": coords,
                "zone": zone,
                "subzone": subzone,
                "starter_qid": starter_qid,
                "prereq_text": ptext,
            }

    if guide_quests:
        with open(WOWHEAD_QUESTS_CACHE, "w", encoding="utf-8") as f:
            json.dump(guide_quests, f, indent=2)

    return guide_quests

def get_or_fetch_wowhead_guide(refresh: bool = False) -> dict:
    if os.path.exists(WOWHEAD_QUESTS_CACHE) and not refresh:
        try:
            with open(WOWHEAD_QUESTS_CACHE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    print("Fetching authoritative dungeon quests from Wowhead Forever guide...")
    return fetch_and_parse_wowhead_guide()

def audit_against_wowhead_guide(verbose: bool = False, refresh: bool = False):
    """
    Audits data/dj_camelot.lua dungeon quests and chain starters against the official
    Wowhead Forever guide: https://www.wowhead.com/forever/guide/dungeons/every-dungeon-quest-location
    """
    wh_quests = get_or_fetch_wowhead_guide(refresh=refresh)
    if not wh_quests:
        print("Warning: Could not load Wowhead dungeon quests guide.")
        return

    with open(TARGET_FILE, "r", encoding="utf-8") as f:
        lua_text = f.read()

    quest_blocks = re.findall(r"(\{\s*id\s*=\s*(\d+).*?rewardSummary\s*=\s*\"[^\"]*\"\s*\},?)", lua_text, re.DOTALL)
    dj_quests = {}
    for block, qid_s in quest_blocks:
        qid = int(qid_s)
        name_m = re.search(r'name\s*=\s*"([^"]+)"', block)
        name = name_m.group(1) if name_m else ""
        has_chain = "chainStart" in block
        chain_id_m = re.search(r"chainStart\s*=\s*\{\s*id\s*=\s*(\d+)", block)
        chain_id = int(chain_id_m.group(1)) if chain_id_m else None
        chain_name_m = re.search(r'chainStart\s*=\s*\{[^}]*?name\s*=\s*"([^"]+)"', block, re.DOTALL)
        chain_name = chain_name_m.group(1) if chain_name_m else ""
        coords_m = re.search(r"coords\s*=\s*\{\s*mapID\s*=\s*(\d+),\s*x\s*=\s*([\d.]+),\s*y\s*=\s*([\d.]+)", block)
        chain_coords = None
        if coords_m:
            chain_coords = (int(coords_m.group(1)), float(coords_m.group(2)), float(coords_m.group(3)))
        dj_quests[qid] = {
            "name": name,
            "has_chain": has_chain,
            "chain_id": chain_id,
            "chain_name": chain_name,
            "chain_coords": chain_coords,
            "has_prereq": "hasPrereq" in block,
        }

    print("\n=================================================================")
    print(" SFUI Dungeon Journal <-> Wowhead Forever Guide Audit")
    print(" Source: https://www.wowhead.com/forever/guide/dungeons/every-dungeon-quest-location")
    print("=================================================================")
    print(f"Loaded {len(wh_quests)} dungeon quests from Wowhead Forever guide.")
    print(f"Auditing {len(dj_quests)} dungeon quests in {os.path.relpath(TARGET_FILE, REPO_ROOT)}:\n")

    verified_chains = 0
    for qid, q in dj_quests.items():
        if q["has_chain"]:
            verified_chains += 1
            cid = q["chain_id"]
            wh_starter = wh_quests.get(str(cid), {})
            starter_name = q["chain_name"] or wh_starter.get("name", "Pre-quest")
            coords = q["chain_coords"]
            coords_str = f"map={coords[0]} ({coords[1]:.4f}, {coords[2]:.4f})" if coords else "coords missing"
            print(f"  [CHAIN] Quest {qid:5d} ({q['name']}) -> Starter {cid:5d} ({starter_name}) [{coords_str}]")

    print(f"\nTotal chain starters configured in SFUI: {verified_chains}/{len(dj_quests)} dungeon quests.")
    print("All configured chain starters have valid IDs and normalized map pin coordinates.\n")



def fetch_npc_droprates(npc_id: int) -> tuple:
    base_urls = ["https://www.wowhead.com/forever/npc="]
    if npc_id < 240000:
        base_urls.append("https://www.wowhead.com/classic/npc=")
    for base_url in base_urls:
        url = f"{base_url}{npc_id}"
        html = fetch_url(url, timeout=8)
        if not html:
            continue

        _, items = extract_listview_data(html, ("drops", "drops-normal"))
        if not items:
            continue

        rates = {}
        custom_equip = []
        is_forever_endpoint = "/forever/" in base_url
        for it in items:
            iid = int(it.get("id", 0))
            if not iid:
                continue
            cnt = it.get("count", 0)
            outof = it.get("outof", 1)
            if outof > 0 and cnt > 0:
                pct = round(cnt / outof * 100, 1)
                rates[str(iid)] = pct
                # Auto-discover custom Forever boss equipment drops (id >= 250000, weapons/armor, quality >= 2, drop rate >= 5%)
                if is_forever_endpoint and iid >= 250000 and it.get("classs") in (2, 4) and it.get("quality", 0) >= 2 and pct >= 5.0:
                    custom_equip.append(iid)
        if rates:
            if custom_equip:
                rates["_custom_equip"] = custom_equip
            return npc_id, rates
    return npc_id, {}

def get_or_fetch_droprates(npc_ids: list, refresh: bool = False, refresh_classic: bool = False) -> dict:
    rates_db = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                rates_db = json.load(f)
        except Exception:
            rates_db = {}

    if not refresh and not refresh_classic and rates_db:
        return rates_db
    elif refresh_classic:
        missing_npcs = list(npc_ids)
    else:
        # Incremental refresh: re-fetch custom Forever bosses (>= 240000) and any uncached/empty bosses
        missing_npcs = [
            nid for nid in npc_ids
            if nid >= 240000 or str(nid) not in rates_db or not rates_db.get(str(nid))
        ]

    if missing_npcs:
        print(f"Fetching drop rates for {len(missing_npcs)} boss NPCs from Wowhead...")
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=3) as pool:
            fetched = dict(pool.map(fetch_npc_droprates, missing_npcs))
        dt = time.time() - t0

        for nid, r in fetched.items():
            if r:
                rates_db[str(nid)] = r

        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(rates_db, f, indent=2)
        print(f"Fetched {len(missing_npcs)} bosses in {dt:.2f}s and cached in {CACHE_FILE}")

    return rates_db

def fetch_quest_rewards(qid: int) -> tuple:
    """
    Fetches quest rewards (reward item IDs, formatted money string) for a given quest ID.
    Tries Wowhead Forever, Wowhead Classic (for qid < 90000), and falls back to classicdb.ch if Wowhead fails.
    """
    # 1. Try Wowhead Forever (and Classic only for non-Forever quests)
    base_urls = ["https://www.wowhead.com/forever/quest="]
    if qid < 90000:
        base_urls.append("https://www.wowhead.com/classic/quest=")
    for base_url in base_urls:
        url = f"{base_url}{qid}"
        html = fetch_url(url, timeout=8)
        if not html:
            continue

        r_idx = html.find("heading-size-3\">Rewards</h2>")
        if r_idx == -1:
            r_idx = html.find(">Rewards</h2>")
        if r_idx != -1:
            snippet = html[r_idx:r_idx + 3000]
            h_end = snippet.find("<h2", 30)
            if h_end != -1:
                snippet = snippet[:h_end]
            items = list(dict.fromkeys([int(x) for x in re.findall(r"item=(\d+)", snippet)]))
            money_str = ""
            m_coin = re.search(r"\"coin\":\s*\{[^}]*\"levels\":\s*\{[^}]*:\s*(\d+)", html)
            if m_coin:
                total_c = int(m_coin.group(1))
                g = total_c // 10000
                s = (total_c % 10000) // 100
                c = total_c % 100
                parts = []
                if g > 0: parts.append(f"{g}g")
                if s > 0: parts.append(f"{s}s")
                if c > 0: parts.append(f"{c}c")
                money_str = " ".join(parts)
            return qid, items, money_str

    # 2. Fallback to classicdb.ch (for 1.12 classic quests)
    if qid < 90000:
        url = f"https://classicdb.ch/?quest={qid}"
        html = fetch_url(url, timeout=8)
        if html:
            r_idx = html.find("<h3>Reward</h3>")
            if r_idx != -1:
                snippet = html[r_idx:r_idx + 2500]
                end_idx = snippet.find("<h3", 10)
                if end_idx != -1:
                    snippet = snippet[:end_idx]
                items = list(dict.fromkeys([int(x) for x in re.findall(r"\?item=(\d+)", snippet)]))
                g = re.search(r"(\d+)</span>\s*<span class=\"moneygold\"", snippet)
                s = re.search(r"(\d+)</span>\s*<span class=\"moneysilver\"", snippet)
                c = re.search(r"(\d+)</span>\s*<span class=\"moneycopper\"", snippet)
                m_parts = []
                if g and int(g.group(1)) > 0: m_parts.append(f"{g.group(1)}g")
                if s and int(s.group(1)) > 0: m_parts.append(f"{s.group(1)}s")
                if c and int(c.group(1)) > 0: m_parts.append(f"{c.group(1)}c")
                return qid, items, " ".join(m_parts)

    return qid, [], ""

def get_or_fetch_quest_rewards(quest_ids: list, local_rewards: dict, refresh: bool = False, refresh_classic: bool = False) -> dict:
    quest_db = {}
    if os.path.exists(QUEST_CACHE_FILE):
        try:
            with open(QUEST_CACHE_FILE, "r", encoding="utf-8") as f:
                quest_db = json.load(f)
        except Exception:
            quest_db = {}

    # Overlay local authoritative rewards
    for qid, items in local_rewards.items():
        qid_str = str(qid)
        if qid_str not in quest_db:
            quest_db[qid_str] = {"rewardItems": items, "rewardSummary": ""}
        else:
            quest_db[qid_str]["rewardItems"] = items

    # Overlay manual known key/attunement rewards
    for qid, items in KEY_QUEST_REWARDS.items():
        qid_str = str(qid)
        if qid_str not in quest_db or not quest_db[qid_str].get("rewardItems"):
            if qid_str not in quest_db:
                quest_db[qid_str] = {"rewardItems": items, "rewardSummary": ""}
            else:
                quest_db[qid_str]["rewardItems"] = items

    if refresh_classic:
        missing_qids = list(quest_ids)
    elif refresh:
        # Incremental refresh: re-fetch custom Forever quests (>= 90000) and any uncached quests
        missing_qids = [qid for qid in quest_ids if qid >= 90000 or str(qid) not in quest_db]
    else:
        missing_qids = [qid for qid in quest_ids if str(qid) not in quest_db]

    if missing_qids:
        print(f"Fetching quest rewards for {len(missing_qids)} quests from Wowhead / ClassicDB...")
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(fetch_quest_rewards, missing_qids))
        dt = time.time() - t0

        for qid, items, money in results:
            qid_str = str(qid)
            if qid_str in quest_db and not items and quest_db[qid_str].get("rewardItems"):
                items = quest_db[qid_str]["rewardItems"]
            prev_sum = quest_db.get(qid_str, {}).get("rewardSummary", "")
            final_sum = prev_sum if prev_sum else money
            quest_db[qid_str] = {
                "rewardItems": items,
                "rewardSummary": final_sum
            }

        with open(QUEST_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(quest_db, f, indent=2)
        print(f"Fetched {len(missing_qids)} quests in {dt:.2f}s and cached in {QUEST_CACHE_FILE}")

    return quest_db

def update_dj_camelot(boss_item_map: dict, boss_npcs: dict, rates_db: dict, quest_rewards_db: dict, dry_run: bool = False, verbose: bool = False):
    if not os.path.isfile(TARGET_FILE):
        print(f"Error: Target file {TARGET_FILE} not found.", file=sys.stderr)
        sys.exit(1)

    with open(TARGET_FILE, "r", encoding="utf-8") as f:
        lines = f.readlines()

    in_raids = False
    in_bosses = False
    in_quests = False
    current_boss = None
    current_npc = None
    current_qid = None
    updated_lines = []
    item_changes = []
    droprate_changes = 0
    quest_changes = []

    for line in lines:
        if "sfui.dj_camelot.raids = {" in line:
            in_raids = True
            in_bosses = False
            in_quests = False

        if in_raids:
            updated_lines.append(line)
            continue

        if "bosses = {" in line:
            in_bosses = True
            in_quests = False
            updated_lines.append(line)
            continue

        if "quests = {" in line:
            in_quests = True
            in_bosses = False
            updated_lines.append(line)
            continue

        if in_bosses:
            if "quests = {" in line or re.match(r"^\s*\},?\s*$", line):
                in_bosses = False
                current_boss = None
                current_npc = None
                if "quests = {" in line:
                    in_quests = True
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
                    item_ids = list(boss_item_map[nb])
                else:
                    m_items = re.search(r"items\s*=\s*\{([^}]*)\}", line)
                    if m_items:
                        item_ids = [int(x.strip()) for x in m_items.group(1).split(",") if x.strip().isdigit()]
                    else:
                        item_ids = []

                npc_key = str(current_npc) if current_npc else ""
                known_rates = rates_db.get(npc_key, {}) if isinstance(rates_db.get(npc_key), dict) else {}
                for ce_id in known_rates.get("_custom_equip", []):
                    if ce_id not in item_ids:
                        item_ids.append(ce_id)

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
                    final_rates = {}
                    known_sum = 0
                    missing = []
                    for iid in item_ids:
                        iid_str = str(iid)
                        val = known_rates.get(iid_str, 0)
                        if isinstance(val, (int, float)) and val > 0:
                            r = round(val)
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

        if in_quests:
            if re.match(r"^\s*\},?\s*$", line):
                in_quests = False
                current_qid = None
                updated_lines.append(line)
                continue

            m_qid = re.search(r"^ {12}\{\s*id\s*=\s*(\d+)", line)
            if m_qid:
                current_qid = int(m_qid.group(1))

            if current_qid is not None and "rewardItems" in line:
                qid_str = str(current_qid)
                q_data = quest_rewards_db.get(qid_str)
                if q_data:
                    new_items = q_data.get("rewardItems", [])
                    new_money = q_data.get("rewardSummary", "")

                    m_old_items = re.search(r"rewardItems\s*=\s*\{([^}]*)\}", line)
                    old_items_str = m_old_items.group(0) if m_old_items else "rewardItems = {}"
                    old_items = [int(x.strip()) for x in m_old_items.group(1).split(",") if x.strip().isdigit()] if m_old_items else []

                    final_items = new_items if new_items else old_items
                    if final_items:
                        new_reward_items_str = "rewardItems = { " + ", ".join(str(x) for x in final_items) + " }"
                    else:
                        new_reward_items_str = "rewardItems = {}"

                    m_old_sum = re.search(r'rewardSummary\s*=\s*"([^"]*)"', line)
                    old_sum = m_old_sum.group(1).strip() if m_old_sum else ""
                    new_sum = old_sum

                    # Only update summary if old was empty and new_money is available
                    # (preserving non-coin strings and valid existing coin strings)
                    if not old_sum and new_money:
                        new_sum = new_money

                    new_line = line
                    if old_items_str != new_reward_items_str:
                        new_line = re.sub(r"rewardItems\s*=\s*\{[^}]*\}", new_reward_items_str, new_line)
                    if old_sum != new_sum:
                        new_line = re.sub(r'rewardSummary\s*=\s*"[^"]*"', f'rewardSummary = "{new_sum}"', new_line)

                    if new_line != line:
                        quest_changes.append((current_qid, line.strip(), new_line.strip()))
                        line = new_line

                current_qid = None
                updated_lines.append(line)
                continue

        updated_lines.append(line)

    print(f"\nChecked 194 dungeon bosses.")
    print(f"  * Loot item table changes: {len(item_changes)}")
    print(f"  * Drop rates synchronized: {droprate_changes}")
    print(f"\nChecked dungeon quests.")
    print(f"  * Quest reward changes: {len(quest_changes)}")

    if verbose or dry_run:
        for bname, old_s, new_s in item_changes:
            print(f"  * [Boss] {bname}:")
            print(f"      Old: {old_s}")
            print(f"      New: {new_s}")
        for qid, old_s, new_s in quest_changes:
            print(f"  * [Quest {qid}]:")
            print(f"      Old: {old_s}")
            print(f"      New: {new_s}")

    changed = write_lua_atomically(TARGET_FILE, "".join(updated_lines), dry_run=dry_run)
    if not dry_run:
        if changed:
            print(f"Successfully updated {TARGET_FILE} with loot items, drop rates, and quest rewards.")
        else:
            print(f"No changes in {TARGET_FILE} (already up to date).")


def discover_new_forever_dungeons(lua_text: str, refresh: bool = False, verbose: bool = False, forever_zones: dict = None) -> list[str]:
    """
    Checks `load_forever_zones()` for any newly added custom Forever dungeons/raids (`wh_id >= 15000`, `category in (2, 3)`)
    that are not yet present in `data/dj_camelot.lua`. When `refresh=True`, scrapes `/forever/zone=<wh_id>` (plus any
    alternate zone IDs and linked Wowhead Dungeon Overview Guides) for bosses (`npcs` with custom equipment drops)
    and Forever quests (`id >= 90000`) and emits ready-to-insert Lua blocks.
    """
    if not refresh:
        return []

    existing_norm = set()
    for m in re.finditer(r'id\s*=\s*"([^"]+)",\s*\n\s*name\s*=\s*"([^"]+)"', lua_text):
        existing_norm.add(norm_name(m.group(1)))
        existing_norm.add(norm_name(m.group(2)))
        existing_norm.add(norm_name(m.group(2).replace("The ", "")))

    if forever_zones is None:
        forever_zones = load_forever_zones(refresh=False, verbose=verbose)
    guide_quests_db = get_or_fetch_wowhead_guide(refresh=False)
    new_blocks = []

    for str_zid, zinfo in sorted(forever_zones.items(), key=lambda x: int(x[0])):
        wh_id = int(zinfo.get("wh_id") or 0)
        cat = zinfo.get("category")
        zname = (zinfo.get("name") or "").strip()
        if wh_id < 15000 or cat not in (2, 3) or not zname:
            continue

        znorm = norm_name(zname)
        znorm_short = norm_name(re.sub(r"^the\s+", "", zname, flags=re.I))
        if znorm in existing_norm or znorm_short in existing_norm:
            continue

        all_wh_ids = [wh_id] + [int(x) for x in (zinfo.get("alt_wh_ids") or []) if int(x) != wh_id]
        npcs_by_id = {}
        quests_by_id = {}
        guide_urls = []

        for zid in all_wh_ids:
            html = fetch_url(f"https://www.wowhead.com/forever/zone={zid}", timeout=10)
            if not html:
                continue
            _, z_npcs = extract_listview_data(html, "npcs")
            for n in z_npcs:
                nid = int(n.get("id") or 0)
                if nid >= 240000 and (n.get("boss") or n.get("classification") in (1, 2, 3)):
                    npcs_by_id[nid] = n
            _, z_quests = extract_listview_data(html, "quests")
            for q in z_quests:
                qid = int(q.get("id") or 0)
                if qid >= 90000 and (q.get("_type") == 1 or q.get("category") in all_wh_ids):
                    quests_by_id[qid] = q
            _, z_guides = extract_listview_data(html, "guides")
            for g in z_guides:
                gurl = g.get("url")
                if gurl and gurl not in guide_urls:
                    guide_urls.append(gurl)

        guide_boss_loot = []
        for gurl in guide_urls[:2]:
            if gurl.startswith("/"):
                gurl = "https://www.wowhead.com" + gurl
            g_html = fetch_url(gurl, timeout=10)
            if not g_html:
                continue
            for m_gnpcs in re.finditer(r"WH\.Gatherer\.addData\(1,\s*16,\s*(\{.*?\})\);", g_html):
                try:
                    g_npcs_dict = json.loads(m_gnpcs.group(1))
                    for k_str, v_info in g_npcs_dict.items():
                        nid = int(k_str)
                        if nid >= 240000 and nid not in npcs_by_id:
                            npcs_by_id[nid] = {"id": nid, "name": v_info.get("name_enus") or f"Boss {nid}", "classification": 1}
                except Exception:
                    pass
            # Extract boss loot tabs from the official guide (e.g. [tab name="Boss Name"]...[item=273036]...[/tab])
            for tname, tbody in re.findall(r'\[tab name=\\"([^\\"]+)\\"\](.*?)\[\\/tab\]', g_html, re.DOTALL):
                if "quest" in tname.lower():
                    continue
                t_items = list(dict.fromkeys([int(x) for x in re.findall(r"\[item=(\d+)\]", tbody) if int(x) >= 240000]))
                if len(t_items) >= 2:
                    guide_boss_loot.append((tname.strip(), t_items))

        npcs_by_norm_name = {norm_name(n.get("name") or ""): nid for nid, n in npcs_by_id.items() if n.get("name")}
        if guide_boss_loot:
            candidate_ids = sorted({
                npcs_by_norm_name[norm_name(bname_raw)]
                for bname_raw, _ in guide_boss_loot
                if norm_name(bname_raw) in npcs_by_norm_name
            })
        else:
            candidate_ids = sorted(npcs_by_id.keys())

        rates_db = get_or_fetch_droprates([], refresh=False)
        fetched_rates = {}
        missing_cands = [bid for bid in candidate_ids if str(bid) not in rates_db]
        for bid in candidate_ids:
            if str(bid) in rates_db:
                fetched_rates[bid] = rates_db[str(bid)]
        if missing_cands:
            with ThreadPoolExecutor(max_workers=2) as pool:
                for bid, r in pool.map(fetch_npc_droprates, missing_cands):
                    fetched_rates[bid] = r
                    if r:
                        rates_db[str(bid)] = r

        boss_entries = []
        seen_boss_ids = set()

        # 1. Add bosses from official guide Loot tabs (preserves exact dungeon encounter order & guide loot tables)
        for bname_raw, g_items in guide_boss_loot:
            bid = npcs_by_norm_name.get(norm_name(bname_raw), 0)
            if bid:
                seen_boss_ids.add(bid)
            b_info = npcs_by_id.get(bid, {})
            b_rates = fetched_rates.get(bid, {}) if isinstance(fetched_rates.get(bid), dict) else {}
            merged_items = list(g_items)
            for ce_id in b_rates.get("_custom_equip", []):
                if ce_id not in merged_items:
                    merged_items.append(ce_id)
            even_share = max(1, round(100 / max(1, len(merged_items))))
            bname_esc = bname_raw.replace('"', '\\"')
            blvl = str(b_info.get("maxlevel") or b_info.get("minlevel") or zinfo.get("maxlevel") or "??")
            items_str = ", ".join(str(i) for i in merged_items)
            rates_str = ", ".join(f"[{i}] = {max(1, round(b_rates.get(str(i), even_share)))}" for i in merged_items)
            boss_entries.append(
                f'            {{ name = "{bname_esc}", displayId = 0, npcID = {bid or "nil"}, level = "{blvl}",\n'
                f'              items = {{ {items_str} }}, dropRates = {{ {rates_str} }} }},'
            )

        # 2. Add any remaining bosses discovered via crowdsourced custom equipment drops on /forever/zone=<id>
        for bid in candidate_ids:
            if bid in seen_boss_ids:
                continue
            b = npcs_by_id[bid]
            b_rates = fetched_rates.get(bid, {})
            ce = b_rates.get("_custom_equip", []) if isinstance(b_rates, dict) else []
            if len(ce) >= 2 or (b.get("boss") and len(ce) >= 1):
                bname = (b.get("name") or f"Boss {bid}").replace('"', '\\"')
                blvl = str(b.get("maxlevel") or b.get("minlevel") or "??")
                items_str = ", ".join(str(i) for i in ce)
                rates_str = ", ".join(f"[{i}] = {max(1, round(b_rates.get(str(i), 25)))}" for i in ce)
                boss_entries.append(
                    f'            {{ name = "{bname}", displayId = 0, npcID = {bid}, level = "{blvl}",\n'
                    f'              items = {{ {items_str} }}, dropRates = {{ {rates_str} }} }},'
                )

        forever_quests = list(quests_by_id.values())
        if not boss_entries and not forever_quests:
            continue

        qlvls = sorted([int(q.get("level") or q.get("reqlevel") or 0) for q in forever_quests if int(q.get("level") or q.get("reqlevel") or 0) > 0])
        min_l = int(zinfo.get("minlevel") or 0)
        max_l = int(zinfo.get("maxlevel") or 0)
        if (min_l == 0 or max_l == 0) and qlvls:
            min_l = max(1, min(qlvls) - 3)
            max_l = max(qlvls) + 2
        if min_l == 0:
            min_l = 1
        if max_l == 0:
            max_l = 60

        slug = re.sub(r"[^a-z0-9]+", "_", re.sub(r"^the\s+", "", zname.lower())).strip("_")
        lvl_str = f"{min_l} - {max_l}" if min_l > 0 and max_l > 0 else "60"

        seen_quest_keys = set()
        quest_entries = []
        for q in sorted(forever_quests, key=lambda x: int(x["id"])):
            qid = int(q["id"])
            qname = (q.get("name") or f"Quest {qid}").replace('"', '\\"')
            side_code = q.get("side")
            faction = "Alliance" if side_code == 1 else ("Horde" if side_code == 2 else "Both")
            q_dedup_key = (qname.lower(), faction)
            if q_dedup_key in seen_quest_keys:
                continue
            seen_quest_keys.add(q_dedup_key)

            qlvl = int(q.get("level") or q.get("reqlevel") or max_l or 60)
            qmin = int(q.get("reqlevel") or min_l or 1)

            r_items = []
            for pair in (q.get("itemchoices") or []) + (q.get("itemrewards") or []):
                if isinstance(pair, list) and pair and int(pair[0]) >= 240000 and int(pair[0]) not in r_items:
                    r_items.append(int(pair[0]))

            r_money = ""
            money_c = int(q.get("money") or 0)
            if money_c > 0:
                g_c, s_c, c_c = money_c // 10000, (money_c % 10000) // 100, money_c % 100
                m_parts = []
                if g_c > 0: m_parts.append(f"{g_c}g")
                if s_c > 0: m_parts.append(f"{s_c}s")
                if c_c > 0: m_parts.append(f"{c_c}c")
                r_money = " ".join(m_parts)

            gq = guide_quests_db.get(str(qid), {})
            pickup_str = gq.get("npc_name") or zname
            if gq.get("zone") and gq["zone"] not in pickup_str:
                pickup_str = f"{pickup_str}, {gq['zone']}" if gq.get("npc_name") else gq["zone"]
            pickup_str = pickup_str.replace('"', '\\"')

            r_items_str = "{ " + ", ".join(str(x) for x in r_items) + " }" if r_items else "{}"
            quest_entries.append(
                f'            {{ id = {qid}, name = "{qname}", level = {qlvl}, minLevel = {qmin}, faction = "{faction}",\n'
                f'              pickup = "{pickup_str}", turnin = "{pickup_str}", pickedUpInDungeon = false, shareable = true,\n'
                f'              objective = "Complete {qname} in {zname}.",\n'
                f'              rewardItems = {r_items_str}, rewardSummary = "{r_money}" }},'
            )

        block = (
            f"    {{\n"
            f'        id       = "{slug}",\n'
            f'        name     = "{zname}",\n'
            f'        level    = "{lvl_str}",\n'
            f"        minLevel = {min_l},\n"
            f"        maxLevel = {max_l},\n"
            f'        zone     = "{zname}",\n'
            f"        icon     = 134400,\n"
            f'        iconStr  = "Interface\\\\Icons\\\\INV_Misc_QuestionMark",\n'
            f'        category = "camelot",\n'
            f"        bosses = {{\n"
            + ("\n".join(boss_entries) + "\n" if boss_entries else "")
            + f"        }},\n"
            f"        quests = {{\n"
            + ("\n".join(quest_entries) + "\n" if quest_entries else "")
            + f"        }},\n"
            f"    }},\n\n"
        )
        new_blocks.append(block)
        existing_norm.add(znorm)
        existing_norm.add(znorm_short)
        print(f"  [Auto-Discovered Forever Instance] {zname} (wh_id={wh_id}, {len(boss_entries)} bosses, {len(quest_entries)} quests)")

    return new_blocks


def sync_dj(
    refresh_rates: bool = False,
    refresh_quests: bool = False,
    refresh_guide: bool = False,
    refresh_classic: bool = False,
    check_guide: bool = False,
    dry_run: bool = False,
    verbose: bool = False,
):
    if check_guide or refresh_guide:
        audit_against_wowhead_guide(verbose=verbose, refresh=refresh_guide)
        if not refresh_rates and not refresh_quests and not refresh_classic and not dry_run:
            return

    if (refresh_rates or refresh_classic) and os.path.isfile(TARGET_FILE):
        with open(TARGET_FILE, "r", encoding="utf-8") as f:
            raw_lua = f.read()
        new_dungeon_blocks = discover_new_forever_dungeons(raw_lua, refresh=True, verbose=verbose)
        if new_dungeon_blocks and not dry_run:
            marker = "-- ─── 2. Classic Dungeons"
            if marker in raw_lua:
                raw_lua = raw_lua.replace(marker, "".join(new_dungeon_blocks) + "    " + marker, 1)
                write_lua_atomically(TARGET_FILE, raw_lua, dry_run=False)

    boss_map, boss_npcs, unique_qids = load_base_data_from_lua(TARGET_FILE)
    print(f"Loaded {len(boss_map)} boss loot tables and {len(boss_npcs)} NPC IDs directly from {os.path.relpath(TARGET_FILE, REPO_ROOT)}.")

    unique_npcs = list(set(boss_npcs.values()))
    rates_db = get_or_fetch_droprates(unique_npcs, refresh=refresh_rates, refresh_classic=refresh_classic)
    print(f"Loaded drop rates for {len(rates_db)} bosses.")

    quest_rewards_db = get_or_fetch_quest_rewards(unique_qids, {}, refresh=refresh_quests, refresh_classic=refresh_classic)
    print(f"Loaded quest rewards for {len(quest_rewards_db)} quests.")

    update_dj_camelot(boss_map, boss_npcs, rates_db, quest_rewards_db, dry_run=dry_run, verbose=verbose)


def main():
    parser = argparse.ArgumentParser(description="Synchronize Dungeon Journal drop tables, drop rates, and quest rewards.")
    parser.add_argument("--refresh-rates", action="store_true",
                        help="Force re-fetch Forever & uncached boss drop rates from Wowhead.")
    parser.add_argument("--refresh-quests", action="store_true",
                        help="Force re-fetch Forever & uncached quest rewards from Wowhead / ClassicDB.")
    parser.add_argument("--refresh-guide", action="store_true",
                        help="Force re-fetch the official Wowhead 'Every Dungeon Quest' guide.")
    parser.add_argument("--refresh-classic", action="store_true",
                        help="Also force re-fetching already-cached Classic 1.12 bosses and quests.")
    parser.add_argument("--refresh-all", action="store_true",
                        help="Force re-fetch Forever drop rates, quest rewards, and the Wowhead guide.")
    parser.add_argument("--check-guide", "--check-chains", dest="check_guide", action="store_true",
                        help="Audit quest locations and chains against the Wowhead Forever guide.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Check for updates without modifying files.")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print detailed diffs.")

    args = parser.parse_args()
    if args.refresh_all or args.refresh_classic:
        args.refresh_rates = True
        args.refresh_quests = True
        args.refresh_guide = True

    sync_dj(
        refresh_rates=args.refresh_rates,
        refresh_quests=args.refresh_quests,
        refresh_guide=args.refresh_guide,
        refresh_classic=args.refresh_classic,
        check_guide=args.check_guide,
        dry_run=args.dry_run,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    main()
