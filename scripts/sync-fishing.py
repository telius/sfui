#!/usr/bin/env python3
"""
SFUI Fishing Atlas & Waters Synchronizer (Camelot / Classic Forever)
Automates polling catchable fish, containers, empirical drop tables,
and waters distribution from Wowhead Forever endpoints:
  - https://www.wowhead.com/forever/item=
  - https://nether.wowhead.com/forever/tooltip/item/
  - https://www.wowhead.com/forever/items=0.10

Outputs:
  - data/fishing_wowhead.json (raw intermediate scrape cache)
  - data/fishing_camelot.lua  (authoritative Lua database for SFUI on Camelot)

Usage:
    python3 scripts/sync-fishing.py [--refresh] [--dry-run] [--check] [--verbose]
"""

import argparse
import gzip
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA_DIR = os.path.join(REPO_ROOT, "data")
CACHE_FILE = os.path.join(DATA_DIR, "fishing_wowhead.json")
LUA_TARGET = os.path.join(DATA_DIR, "fishing_camelot.lua")

WOWHEAD_BASE = "https://www.wowhead.com/forever"
NETHER_BASE = "https://nether.wowhead.com/forever"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
}

# ─── Seed Catalog of Classic & Forever Fish & Containers ─────────────────────
SEED_SPECIES = {
    # ── Starter / Common Fish ────────────────────────────────────────────────
    6291:  {"name": "raw brilliant smallfish",       "kind": "f"},
    6289:  {"name": "raw longjaw mud snapper",      "kind": "f"},
    6299:  {"name": "raw glossy bay goby",          "kind": "f"},
    6303:  {"name": "raw slitherskin mackerel",     "kind": "f"},
    6317:  {"name": "raw loch frenzy",              "kind": "f"},
    6361:  {"name": "raw rainbow fin albacore",      "kind": "f"},

    # ── Mid-Level Waters ────────────────────────────────────────────────────
    6308:  {"name": "raw bristle whisker catfish",   "kind": "f"},
    6362:  {"name": "raw rockscale cod",            "kind": "f"},
    8365:  {"name": "raw mithril head trout",        "kind": "f"},
    6522:  {"name": "deviate fish",                  "kind": "f"},
    4603:  {"name": "raw spotted yellowtail",        "kind": "f"},
    21071: {"name": "raw sagefish",                  "kind": "f"},

    # ── High-Level & Endgame Waters ─────────────────────────────────────────
    13758: {"name": "raw redgill",                   "kind": "f"},
    13759: {"name": "raw nightfin snapper",          "kind": "f"},
    13760: {"name": "raw sunscale salmon",           "kind": "f"},
    13754: {"name": "raw glossy mightfish",          "kind": "f"},
    13755: {"name": "winter squid",                  "kind": "f"},
    13756: {"name": "summer bass",                   "kind": "f"},
    13757: {"name": "plated armorfish",              "kind": "f"},
    13889: {"name": "raw whitescale salmon",         "kind": "f"},
    21153: {"name": "raw greater sagefish",          "kind": "f"},

    # ── Alchemy & Specialty Seafood ─────────────────────────────────────────
    6358:  {"name": "oily blackmouth",               "kind": "f"},
    6359:  {"name": "firefin snapper",               "kind": "f"},
    13422: {"name": "stonescale eel",                "kind": "f"},
    13888: {"name": "darkclaw lobster",              "kind": "f"},

    # ── Floating Wreckage, Trunks, Clams & Chests ───────────────────────────
    6356:  {"name": "battered chest",                "kind": "c"},
    6353:  {"name": "small battered chest",         "kind": "c"},
    6643:  {"name": "floating wreckage",             "kind": "c"},
    6645:  {"name": "watertight trunk",             "kind": "c"},
    6647:  {"name": "tightly sealed trunk",         "kind": "c"},
    6307:  {"name": "iron bound trunk",             "kind": "c"},
    8366:  {"name": "mithril bound trunk",          "kind": "c"},
    13881: {"name": "large iron bound chest",        "kind": "c"},
    13874: {"name": "heavy iron bound chest",        "kind": "c"},
    13875: {"name": "sturdy locked chest",          "kind": "c"},
    13891: {"name": "ironfeather trunk",             "kind": "c"},
    6351:  {"name": "giant clam",                    "kind": "c"},
    7973:  {"name": "big-mouth clam",               "kind": "c"},
    5523:  {"name": "thick-shelled clam",            "kind": "c"},
    5524:  {"name": "small barnacled clam",         "kind": "c"},

    # ── Quest Catches (Nat Pagle & STV Extravaganza) ─────────────────────────
    16968: {"name": "feralas ahi",                   "kind": "q"},
    16969: {"name": "misty reed mahi mahi",          "kind": "q"},
    16970: {"name": "sar'theris striker",           "kind": "q"},
    16971: {"name": "savage coast blue sailfin",     "kind": "q"},
    19807: {"name": "speckled tastyfish",            "kind": "q"},
    19803: {"name": "keefer's angelfish",            "kind": "q"},
    19805: {"name": "dezian queenfish",             "kind": "q"},
    19806: {"name": "brownell's blue striped racer", "kind": "q"},

    # ── Rare Trophy & Bloated Fish ──────────────────────────────────────────
    13887: {"name": "103 pound mightfish",           "kind": "t"},
    13882: {"name": "22 pound lobster",              "kind": "t"},
    13883: {"name": "32 pound salmon",               "kind": "t"},
    13884: {"name": "42 pound redgill",              "kind": "t"},
    13885: {"name": "53 pound grouper",              "kind": "t"},
    13886: {"name": "68 pound grouper",              "kind": "t"},
    13905: {"name": "14 pound mud snapper",          "kind": "t"},
    13906: {"name": "15 pound mud snapper",          "kind": "t"},
    13907: {"name": "16 pound mud snapper",          "kind": "t"},
    13908: {"name": "17 pound mud snapper",          "kind": "t"},
    13909: {"name": "18 pound mud snapper",          "kind": "t"},
    13910: {"name": "19 pound mud snapper",          "kind": "t"},
    13911: {"name": "20 pound mud snapper",          "kind": "t"},
    13912: {"name": "21 pound mud snapper",          "kind": "t"},
    13913: {"name": "22 pound mud snapper",          "kind": "t"},
    13914: {"name": "29 pound salmon",               "kind": "t"},
    13915: {"name": "32 pound salmon",               "kind": "t"},
    13916: {"name": "41 pound redgill",              "kind": "t"},
    13917: {"name": "52 pound grouper",              "kind": "t"},
}

# Known manual fallbacks for items blocked by CloudFront routing rules
KNOWN_ITEM_FALLBACKS = {
    6317: [  # Raw Loch Frenzy
        {"zone_id": 38, "name": "loch modan", "count": 4821, "outof": 23740}
    ]
}

# ─── Classic UiMap ID Resolution ─────────────────────────────────────────────
ZONE_NAME_TO_UIMAP = {
    "durotar": 1411,
    "mulgore": 1412,
    "the barrens": 1413,
    "barrens": 1413,
    "arathi highlands": 1416,
    "badlands": 1417,
    "alterac mountains": 1418,
    "blasted lands": 1419,
    "tirisfal glades": 1420,
    "silverpine forest": 1421,
    "western plaguelands": 1422,
    "eastern plaguelands": 1423,
    "hillsbrad foothills": 1424,
    "the hinterlands": 1425,
    "hinterlands": 1425,
    "dun morogh": 1426,
    "searing gorge": 1427,
    "burning steppes": 1428,
    "elwynn forest": 1429,
    "deadwind pass": 1430,
    "duskwood": 1431,
    "loch modan": 1432,
    "redridge mountains": 1433,
    "stranglethorn vale": 1434,
    "swamp of sorrows": 1435,
    "westfall": 1436,
    "wetlands": 1437,
    "teldrassil": 1438,
    "darkshore": 1439,
    "ashenvale": 1440,
    "thousand needles": 1441,
    "stonetalon mountains": 1442,
    "desolace": 1443,
    "feralas": 1444,
    "dustwallow marsh": 1445,
    "tanaris": 1446,
    "azshara": 1447,
    "felwood": 1448,
    "un'goro crater": 1449,
    "ungoro crater": 1449,
    "moonglade": 1450,
    "silithus": 1451,
    "winterspring": 1452,
    "stormwind city": 1453,
    "stormwind": 1453,
    "orgrimmar": 1454,
    "ironforge": 1455,
    "thunder bluff": 1456,
    "darnassus": 1457,
    "undercity": 1458,
    "zephras isle": 2521,
}

# Authoritative Zone Minimum Skill Requirements (CMaNGOS classic-db base_level + 95)
AUTHORITATIVE_ZONE_SKILL = {
    # Tier 1 (Skill 25): Starting zones
    1411: 25,  # Durotar
    1412: 25,  # Mulgore
    1420: 25,  # Tirisfal Glades
    1426: 25,  # Dun Morogh
    1429: 25,  # Elwynn Forest
    1438: 25,  # Teldrassil
    2521: 25,  # Zephras Isle (Forever starter zone)

    # Tier 2 (Skill 75): Secondary zones & Capital Cities
    1413: 75,  # The Barrens
    1421: 75,  # Silverpine Forest
    1432: 75,  # Loch Modan
    1436: 75,  # Westfall
    1439: 75,  # Darkshore
    1453: 75,  # Stormwind City
    1454: 75,  # Orgrimmar
    1455: 75,  # Ironforge
    1456: 75,  # Thunder Bluff
    1457: 75,  # Darnassus
    1458: 75,  # Undercity

    # Tier 3 (Skill 150): Mid-level zones
    1424: 150, # Hillsbrad Foothills
    1431: 150, # Duskwood
    1433: 150, # Redridge Mountains
    1437: 150, # Wetlands
    1440: 150, # Ashenvale
    1442: 150, # Stonetalon Mountains

    # Tier 4 (Skill 225): Intermediate zones
    1416: 225, # Arathi Highlands
    1417: 225, # Badlands
    1434: 225, # Stranglethorn Vale
    1435: 225, # Swamp of Sorrows
    1441: 225, # Thousand Needles
    1443: 225, # Desolace
    1445: 225, # Dustwallow Marsh

    # Tier 5 (Skill 300): High-level zones
    1422: 300, # Western Plaguelands
    1425: 300, # The Hinterlands
    1444: 300, # Feralas
    1446: 300, # Tanaris
    1447: 300, # Azshara
    1448: 300, # Felwood
    1449: 300, # Un'Goro Crater
    1450: 300, # Moonglade

    # Tier 6 (Skill 425): Maximum difficulty waters
    1423: 425, # Eastern Plaguelands
    1428: 425, # Burning Steppes
    1430: 425, # Deadwind Pass
    1451: 425, # Silithus
    1452: 425, # Winterspring
}

ZONE_NAMES = {
    1411: "Durotar",
    1412: "Mulgore",
    1413: "The Barrens",
    1416: "Arathi Highlands",
    1417: "Badlands",
    1418: "Alterac Mountains",
    1419: "Blasted Lands",
    1420: "Tirisfal Glades",
    1421: "Silverpine Forest",
    1422: "Western Plaguelands",
    1423: "Eastern Plaguelands",
    1424: "Hillsbrad Foothills",
    1425: "The Hinterlands",
    1426: "Dun Morogh",
    1427: "Searing Gorge",
    1428: "Burning Steppes",
    1429: "Elwynn Forest",
    1430: "Deadwind Pass",
    1431: "Duskwood",
    1432: "Loch Modan",
    1433: "Redridge Mountains",
    1434: "Stranglethorn Vale",
    1435: "Swamp of Sorrows",
    1436: "Westfall",
    1437: "Wetlands",
    1438: "Teldrassil",
    1439: "Darkshore",
    1440: "Ashenvale",
    1441: "Thousand Needles",
    1442: "Stonetalon Mountains",
    1443: "Desolace",
    1444: "Feralas",
    1445: "Dustwallow Marsh",
    1446: "Tanaris",
    1447: "Azshara",
    1448: "Felwood",
    1449: "Un'Goro Crater",
    1450: "Moonglade",
    1451: "Silithus",
    1452: "Winterspring",
    1453: "Stormwind City",
    1454: "Orgrimmar",
    1455: "Ironforge",
    1456: "Thunder Bluff",
    1457: "Darnassus",
    1458: "Undercity",
    2521: "Zephras Isle",
}

# Sub-areas requiring higher skill than the surrounding zone
ZONE_SKILL_PARTS = {
    1434: {"skill": 300, "area": "jaguero isle"},
    1444: {"skill": 425, "area": "jademir lake"},
    1447: {"skill": 425, "area": "bay of storms / scalebeard"},
}

# Classic Lures
LURES = [
    {"itemID": 6533, "skill": 100, "bonus": 100, "name": "aquadynamic fish attractor"},
    {"itemID": 6532, "skill": 100, "bonus": 75,  "name": "bright baubles"},
    {"itemID": 7307, "skill": 100, "bonus": 75,  "name": "flesh eating worm"},
    {"itemID": 6530, "skill": 50,  "bonus": 50,  "name": "nightcrawlers"},
    {"itemID": 6811, "skill": 50,  "bonus": 50,  "name": "aquadynamic fish lens"},
    {"itemID": 6529, "skill": 0,   "bonus": 25,  "name": "shiny bauble"},
]

# Trainer milestone reminders
MILESTONES = {
    75:  {"from": 50,  "text": "learn journeyman fishing from a fishing trainer."},
    150: {"from": 125, "text": "buy 'expert fishing - the bass and you' from old man heming in booty bay."},
    225: {"from": 225, "text": "complete the quest 'nat pagle, angler extreme' (dustwallow marsh) for artisan."},
}

# Camelot Confirmed Local Overrides (e.g. Zephras Isle starter island)
CAMELOT_LOCAL_OVERRIDES = {
    2521: [
        {"itemID": 6291, "share": 53.6, "kind": "f"},
        {"itemID": 6289, "share": 46.4, "kind": "f"},
    ]
}


def norm_name(s: str) -> str:
    if not s:
        return ""
    return re.sub(r"[^a-z0-9]", "", s.lower())


def load_baseline_loot() -> dict:
    """Extracts existing authoritative drop tables from data/fishing_camelot.lua."""
    if not os.path.exists(LUA_TARGET):
        return {}

    try:
        with open(LUA_TARGET, "r", encoding="utf-8") as f:
            lua_text = f.read()

        baseline = {}
        for m in re.finditer(r"\[(\d+)\]\s*=\s*\{\s*(\{.*?\})\s*\}", lua_text):
            uimap = int(m.group(1))
            entries_str = m.group(2)
            entries = []
            for item_m in re.finditer(r"\{\s*(\d+),\s*([0-9.]+),\s*[\x27\x22]([a-z])[\x27\x22]\s*\}", entries_str):
                entries.append({
                    "itemID": int(item_m.group(1)),
                    "share": float(item_m.group(2)),
                    "kind": item_m.group(3)
                })
            if entries:
                baseline[uimap] = entries
        return baseline
    except Exception as e:
        print(f"Warning: Could not read baseline loot from {LUA_TARGET}: {e}", file=sys.stderr)
        return {}


def fetch_url_http(url: str, timeout: int = 10, max_retries: int = 2) -> str:
    """Fetches URL via urllib with gzip decompression."""
    req = urllib.request.Request(url, headers=HEADERS)
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                enc = resp.info().get("Content-Encoding", "").lower()
                if "gzip" in enc or (len(raw) >= 2 and raw[:2] == b"\x1f\x8b"):
                    try:
                        raw = gzip.decompress(raw)
                    except Exception:
                        pass
                return raw.decode("utf-8", errors="ignore")
        except Exception:
            if attempt < max_retries - 1:
                time.sleep(0.5)
    return ""


def extract_fished_in_from_html(html: str) -> list:
    """Extracts fished-in zone list from Wowhead Forever item HTML."""
    if not html:
        return []

    idx = html.find("id: 'fished-in'")
    if idx == -1:
        idx = html.find('id: "fished-in"')
    if idx == -1:
        return []

    idx_data = html.find("data: [", idx)
    if idx_data == -1:
        return []

    depth = 0
    start = idx_data + len("data: ")
    end = -1
    for i in range(start, min(len(html), start + 60000)):
        char = html[i]
        if char == "[":
            depth += 1
        elif char == "]":
            depth -= 1
            if depth == 0:
                end = i + 1
                break

    if end == -1:
        return []

    raw_json = html[start:end]
    try:
        zones = json.loads(raw_json)
        results = []
        for z in zones:
            zid = z.get("id")
            name = z.get("name", "").strip().lower()
            cnt = z.get("count", 0)
            outof = z.get("outof", 1)
            if zid and name and cnt > 0:
                results.append({
                    "zone_id": zid,
                    "name": name,
                    "count": cnt,
                    "outof": outof,
                })
        return results
    except Exception:
        results = []
        for m in re.finditer(r'\{[^{}]*?"id":\s*(\d+)[^{}]*?"name":\s*"([^"]+)"[^{}]*?"count":\s*(\d+)[^{}]*?"outof":\s*(\d+)', raw_json):
            results.append({
                "zone_id": int(m.group(1)),
                "name": m.group(2).lower(),
                "count": int(m.group(3)),
                "outof": int(m.group(4)),
            })
        return results


def fetch_item_metadata_nether(item_id: int) -> dict:
    """Fetches clean item name, quality, and icon from Wowhead Forever CDN."""
    url = f"{NETHER_BASE}/tooltip/item/{item_id}"
    raw = fetch_url_http(url, timeout=6, max_retries=2)
    if not raw:
        return {}
    try:
        data = json.loads(raw)
        return {
            "name": (data.get("name") or "").lower(),
            "quality": int(data.get("quality", 1)),
            "icon": data.get("icon", ""),
        }
    except Exception:
        return {}


def save_cache_file(raw_cache: dict):
    """Safely saves raw scrape cache."""
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(raw_cache, f, indent=2)
    except Exception as e:
        print(f"Warning: Failed to save cache: {e}", file=sys.stderr)


def sync_fishing(refresh: bool = False, dry_run: bool = False, verbose: bool = False, check_only: bool = False):
    """Main synchronization pipeline for fishing atlas and waters."""
    os.makedirs(DATA_DIR, exist_ok=True)

    # 1. Load baseline loot tables from current data/fishing_camelot.lua
    baseline_loot = load_baseline_loot()

    # 2. Load or initialize raw scrape cache
    raw_cache = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                raw_cache = json.load(f)
        except Exception:
            raw_cache = {}

    if check_only:
        print_database_summary(raw_cache)
        return

    # 3. Fetch / Refresh item data from Wowhead Forever
    cache_dirty = False
    items_to_fetch = list(SEED_SPECIES.keys())
    total_items = len(items_to_fetch)
    print(f"Checking {total_items} classic fishing items against Wowhead Forever...")

    for idx, item_id in enumerate(items_to_fetch, start=1):
        cached_entry = raw_cache.get(str(item_id))
        needs_fetch = refresh or not cached_entry or "zones" not in cached_entry or not cached_entry.get("zones")

        if needs_fetch:
            print(f"[{idx}/{total_items}] Polling item {item_id} ({SEED_SPECIES[item_id]['name']}) from Wowhead Forever...")

            zones = []
            if item_id in KNOWN_ITEM_FALLBACKS:
                zones = KNOWN_ITEM_FALLBACKS[item_id]
            else:
                # Try fast HTTP first with ?power
                http_html = fetch_url_http(f"{WOWHEAD_BASE}/item={item_id}?power", timeout=6, max_retries=1)
                zones = extract_fished_in_from_html(http_html)

            # If still empty, check if baseline has zones for this item
            if not zones:
                for uimap, entries in baseline_loot.items():
                    for e in entries:
                        if e["itemID"] == item_id:
                            zname = ZONE_NAMES.get(uimap, "").lower()
                            if zname:
                                zones.append({
                                    "zone_id": uimap,
                                    "name": zname,
                                    "count": int(e["share"] * 100),
                                    "outof": 10000,
                                })

            # Fetch metadata via Nether CDN
            meta = fetch_item_metadata_nether(item_id)

            raw_cache[str(item_id)] = {
                "name": meta.get("name") or SEED_SPECIES[item_id]["name"],
                "kind": SEED_SPECIES[item_id]["kind"],
                "quality": meta.get("quality", 1),
                "icon": meta.get("icon", ""),
                "zones": zones,
                "fetched_at": int(time.time()),
            }
            cache_dirty = True
            save_cache_file(raw_cache)

            if verbose:
                print(f"  -> found {len(zones)} fished-in zones")
            time.sleep(0.05)

    if cache_dirty:
        save_cache_file(raw_cache)
        print(f"Saved raw cache to {CACHE_FILE}")

    # 4. Aggregate catches by Classic UiMap ID (starting with baseline)
    zone_catches = {}
    # Seed from baseline so no zone is ever empty
    for uimap, entries in baseline_loot.items():
        for e in entries:
            zone_catches.setdefault(uimap, []).append({
                "itemID": e["itemID"],
                "count": int(e["share"] * 100),
                "kind": e["kind"],
                "name": SEED_SPECIES.get(e["itemID"], {}).get("name", ""),
            })

    # Overlay empirical catches from Wowhead Forever
    for str_iid, it_data in raw_cache.items():
        iid = int(str_iid)
        kind = it_data.get("kind", "f")
        name = it_data.get("name", "")
        for z in it_data.get("zones", []):
            zname = z.get("name", "").strip().lower()
            cnt = z.get("count", 0)
            uimap = ZONE_NAME_TO_UIMAP.get(zname)
            if not uimap:
                norm_z = norm_name(zname)
                for k, v in ZONE_NAME_TO_UIMAP.items():
                    if norm_name(k) == norm_z:
                        uimap = v
                        break
            if uimap and cnt > 0:
                # Replace or append in zone_catches
                existing = [e for e in zone_catches.setdefault(uimap, []) if e["itemID"] == iid]
                if existing:
                    existing[0]["count"] = cnt
                    existing[0]["kind"] = kind
                else:
                    zone_catches[uimap].append({
                        "itemID": iid,
                        "count": cnt,
                        "kind": kind,
                        "name": name,
                    })

    # 5. Compute drop share percentages per zone
    zone_loot_tables = {}
    for uimap, entries in zone_catches.items():
        total_counts = sum(e["count"] for e in entries)
        if total_counts <= 0:
            continue

        loot_list = []
        for e in entries:
            share = round((e["count"] / total_counts) * 100.0, 1)
            if share >= 0.1:  # Filter noise below 0.1%
                loot_list.append({
                    "itemID": e["itemID"],
                    "share": share,
                    "kind": e["kind"],
                    "count": e["count"],
                })

        # Sort descending by share
        loot_list.sort(key=lambda x: (x["share"], x["count"]), reverse=True)

        # Normalize sum to exactly 100.0
        if loot_list:
            current_sum = sum(x["share"] for x in loot_list)
            drift = round(100.0 - current_sum, 1)
            if abs(drift) <= 1.0 and abs(drift) > 0.0:
                loot_list[0]["share"] = round(loot_list[0]["share"] + drift, 1)

        zone_loot_tables[uimap] = [[x["itemID"], x["share"], x["kind"]] for x in loot_list]

    # Incorporate Camelot local overrides
    for uimap, entries in CAMELOT_LOCAL_OVERRIDES.items():
        zone_loot_tables[uimap] = [[e["itemID"], e["share"], e["kind"]] for e in entries]

    # 6. Generate data/fishing_camelot.lua
    generate_lua_database(zone_loot_tables, raw_cache, dry_run=dry_run)
    print_database_summary(raw_cache, zone_loot_tables)


def generate_lua_database(zone_loot_tables: dict, raw_cache: dict, dry_run: bool = False):
    """Generates clean authoritative data/fishing_camelot.lua file."""
    lines = []
    lines.append("local addonName, addon = ...")
    lines.append("sfui = sfui or {}")
    lines.append("sfui.fishing_data = sfui.fishing_data or {}")
    lines.append("")
    lines.append("-- " + "═" * 78)
    lines.append("--  sfui/data/fishing_camelot.lua")
    lines.append("--  Authoritative Fishing Data for Camelot & Classic Forever")
    lines.append("--")
    lines.append("--  Synchronized automatically from Wowhead Forever endpoints.")
    lines.append("--  Zone skill thresholds, classic lures, and empirical zone loot tables.")
    lines.append("-- " + "═" * 78)
    lines.append("")
    lines.append("local D = sfui.fishing_data")
    lines.append("local pairs, ipairs, tonumber = pairs, ipairs, tonumber")
    lines.append("local table_sort = table.sort")
    lines.append("")

    # ── 1. Classic Lures ─────────────────────────────────────────────────────
    lines.append("-- ─── 1. Classic Lures ────────────────────────────────────────────────────────")
    lines.append("-- Ordered best first. skill = required fishing rank, bonus = added fishing skill.")
    lines.append("D.LURES = {")
    for lure in LURES:
        lines.append(f'    {{ itemID = {lure["itemID"]}, skill = {lure["skill"]}, bonus = {lure["bonus"]}, name = "{lure["name"]}" }},')
    lines.append("}")
    lines.append("")
    lines.append("-- Fast lookup of known lure item IDs")
    lines.append("D.LURE_ITEM_IDS = {}")
    lines.append("for _, lure in ipairs(D.LURES) do")
    lines.append("    D.LURE_ITEM_IDS[lure.itemID] = lure")
    lines.append("end")
    lines.append("")

    # ── 2. Zone Skill Requirements ───────────────────────────────────────────
    lines.append("-- ─── 2. Zone Skill Requirements ──────────────────────────────────────────────")
    lines.append("-- Minimum fishing skill (base + lure + gear) needed for 0% escape rate by classic UiMap ID.")
    lines.append("-- Calculation: CMaNGOS classic-db base_level + 95.")
    lines.append("D.ZONE_SKILL = {")
    for uimap in sorted(AUTHORITATIVE_ZONE_SKILL.keys()):
        req = AUTHORITATIVE_ZONE_SKILL[uimap]
        zname = ZONE_NAMES.get(uimap, f"Map {uimap}")
        lines.append(f"    [{uimap}] = {req},  -- {zname}")
    lines.append("}")
    lines.append("")

    # Sub-areas
    lines.append("-- Sub-areas requiring higher skill than the surrounding zone")
    lines.append("D.ZONE_SKILL_PARTS = {")
    for uimap, p in sorted(ZONE_SKILL_PARTS.items()):
        lines.append(f'    [{uimap}] = {{ skill = {p["skill"]}, area = "{p["area"]}" }},')
    lines.append("}")
    lines.append("")

    # Milestones
    lines.append("-- Trainer milestone reminders")
    lines.append("D.MILESTONES = {")
    for cap, m in sorted(MILESTONES.items()):
        lines.append(f'    [{cap}] = {{ from = {m["from"]}, text = "{m["text"]}" }},')
    lines.append("}")
    lines.append("")

    # ── 3. Zone Loot Tables ──────────────────────────────────────────────────
    lines.append("-- ─── 3. Zone Loot Tables ─────────────────────────────────────────────────────")
    lines.append("-- Mapping: [mapID] = { { itemID, sharePercent, kind }, ... }")
    lines.append('-- kind: "f" = fish, "c" = container / trunk / chest / clam, "q" = quest, "t" = trophy')

    # Primary unified zones (starting zones, secondary, capital cities)
    primary_zones = [1411, 1412, 1413, 1420, 1421, 1424, 1426, 1429, 1431, 1432, 1433, 1436, 1437, 1438, 1439, 1440, 1442, 1453, 1454, 1455, 1456, 1457, 1458, 2521]
    lines.append("D.ZONE_FISH = {")
    for uimap in sorted(primary_zones):
        loot = zone_loot_tables.get(uimap)
        if loot:
            zname = ZONE_NAMES.get(uimap, f"Map {uimap}")
            entries_str = ", ".join(f'{{ {item[0]}, {item[1]}, "{item[2]}" }}' for item in loot)
            lines.append(f"    [{uimap}] = {{ {entries_str} }}, -- {zname}")
    lines.append("}")
    lines.append("")

    # Classic higher-level zones (level 30+ waters)
    classic_zones = [k for k in AUTHORITATIVE_ZONE_SKILL.keys() if k not in primary_zones]
    lines.append("-- Higher-level zones (Level 30+) and contested waters")
    lines.append("D.ZONE_FISH_CLASSIC = {")
    for uimap in sorted(classic_zones):
        loot = zone_loot_tables.get(uimap)
        if loot:
            zname = ZONE_NAMES.get(uimap, f"Map {uimap}")
            entries_str = ", ".join(f'{{ {item[0]}, {item[1]}, "{item[2]}" }}' for item in loot)
            lines.append(f"    [{uimap}] = {{ {entries_str} }}, -- {zname}")
    lines.append("}")
    lines.append("")

    # ── 4. Species Catalog Builder ───────────────────────────────────────────
    lines.append("-- ─── 4. Pre-Indexed Catalog of All Species ───────────────────────────────────")
    lines.append("local speciesCatalog = nil")
    lines.append("")
    lines.append("local function BuildSpeciesCatalog()")
    lines.append("    if speciesCatalog then return speciesCatalog end")
    lines.append("    speciesCatalog = {}")
    lines.append("")
    lines.append("    local function add_list(list, isClassic)")
    lines.append("        for mapID, fishEntries in pairs(list) do")
    lines.append("            for _, entry in ipairs(fishEntries) do")
    lines.append("                local itemID = entry[1]")
    lines.append("                local share = entry[2]")
    lines.append("                local kind = entry[3]")
    lines.append("")
    lines.append("                local item = speciesCatalog[itemID]")
    lines.append("                if not item then")
    lines.append("                    item = {")
    lines.append("                        itemID = itemID,")
    lines.append("                        kind = kind,")
    lines.append('                        isContainer = (kind == "c"),')
    lines.append("                        zones = {},")
    lines.append("                        minSkill = 9999,")
    lines.append("                    }")
    lines.append("                    speciesCatalog[itemID] = item")
    lines.append("                end")
    lines.append("")
    lines.append("                local reqSkill = D.ZONE_SKILL[mapID] or 0")
    lines.append("                if reqSkill > 0 and reqSkill < item.minSkill then")
    lines.append("                    item.minSkill = reqSkill")
    lines.append("                end")
    lines.append("")
    lines.append("                table.insert(item.zones, {")
    lines.append("                    mapID = mapID,")
    lines.append("                    share = share,")
    lines.append("                    isClassic = isClassic,")
    lines.append("                    reqSkill = reqSkill,")
    lines.append("                })")
    lines.append("            end")
    lines.append("        end")
    lines.append("    end")
    lines.append("")
    lines.append("    add_list(D.ZONE_FISH, false)")
    lines.append("    add_list(D.ZONE_FISH_CLASSIC, true)")
    lines.append("")
    lines.append("    -- Sort zones per fish by highest drop percentage")
    lines.append("    for _, item in pairs(speciesCatalog) do")
    lines.append("        if item.minSkill == 9999 then item.minSkill = 0 end")
    lines.append("        table_sort(item.zones, function(a, b)")
    lines.append("            return (a.share or 0) > (b.share or 0)")
    lines.append("        end)")
    lines.append("    end")
    lines.append("")
    lines.append("    return speciesCatalog")
    lines.append("end")
    lines.append("")

    # ── 5. Public Query API ──────────────────────────────────────────────────
    lines.append("-- ─── 5. Public Query API ─────────────────────────────────────────────────────")
    lines.append("")
    lines.append("--- Returns the required fishing skill for a given mapID")
    lines.append("--- @param mapID number")
    lines.append("--- @return number requiredSkill, string|nil subAreaHint")
    lines.append("function D.GetZoneRequirement(mapID)")
    lines.append("    if not mapID or mapID <= 0 then return nil end")
    lines.append("    local req = D.ZONE_SKILL[mapID]")
    lines.append("    local sub = D.ZONE_SKILL_PARTS[mapID]")
    lines.append("    return req, sub")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns loot table entries for a specific zone")
    lines.append("--- @param mapID number")
    lines.append("--- @return table|nil entries, boolean isClassicOnly")
    lines.append("function D.GetZoneLoot(mapID)")
    lines.append("    if not mapID or mapID <= 0 then return nil, false end")
    lines.append("    if D.ZONE_FISH[mapID] then")
    lines.append("        return D.ZONE_FISH[mapID], false")
    lines.append("    elseif D.ZONE_FISH_CLASSIC[mapID] then")
    lines.append("        return D.ZONE_FISH_CLASSIC[mapID], true")
    lines.append("    end")
    lines.append("    return nil, false")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns catalog item for a specific fish/container itemID")
    lines.append("--- @param itemID number")
    lines.append("--- @return table|nil")
    lines.append("function D.GetSpeciesInfo(itemID)")
    lines.append("    local catalog = BuildSpeciesCatalog()")
    lines.append("    return catalog and catalog[itemID]")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns the full list of all cataloged species")
    lines.append("--- @return table")
    lines.append("function D.GetAllSpecies()")
    lines.append("    return BuildSpeciesCatalog()")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns all known fishing zones with their requirement")
    lines.append("--- @return table array of { mapID, reqSkill, sub }")
    lines.append("function D.GetAllWaters()")
    lines.append("    local waters = {}")
    lines.append("    for mapID, req in pairs(D.ZONE_SKILL) do")
    lines.append("        waters[#waters + 1] = {")
    lines.append("            mapID = mapID,")
    lines.append("            reqSkill = req,")
    lines.append("            sub = D.ZONE_SKILL_PARTS[mapID],")
    lines.append("        }")
    lines.append("    end")
    lines.append("    table_sort(waters, function(a, b)")
    lines.append("        if a.reqSkill ~= b.reqSkill then")
    lines.append("            return a.reqSkill < b.reqSkill")
    lines.append("        end")
    lines.append("        return a.mapID < b.mapID")
    lines.append("    end)")
    lines.append("    return waters")
    lines.append("end")
    lines.append("")
    lines.append("-- ─── Lure Detection & Memoized Bag Cache ─────────────────────────────────────")
    lines.append("local cachedLure = nil")
    lines.append("local cachedLureRank = nil")
    lines.append("local lureCacheDirty = true")
    lines.append("")
    lines.append("function D.InvalidateLureCache()")
    lines.append("    lureCacheDirty = true")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns best bag lure that the player can use given their current skill rank")
    lines.append("--- @param skillRank number")
    lines.append("--- @return table|nil { itemID, bonus, bag, slot, link, count }")
    lines.append("function D.FindBestLureInBags(skillRank)")
    lines.append("    skillRank = skillRank or 0")
    lines.append("    if not lureCacheDirty and cachedLureRank == skillRank then")
    lines.append("        return cachedLure")
    lines.append("    end")
    lines.append("")
    lines.append("    local common = sfui.common")
    lines.append("    if not common or not common.for_each_bag_item then return nil end")
    lines.append("")
    lines.append("    local bestItemID, bestName, bestBonus, bestSkill, bestBag, bestSlot, bestLink, bestCount = nil, nil, -1, 0, nil, nil, nil, 0")
    lines.append("    local C_Container = _G.C_Container")
    lines.append("")
    lines.append("    common.for_each_bag_item(function(bag, slot, itemID, itemLink)")
    lines.append("        if itemID and D.LURE_ITEM_IDS[itemID] then")
    lines.append("            local lureDef = D.LURE_ITEM_IDS[itemID]")
    lines.append("            if skillRank >= lureDef.skill then")
    lines.append("                if lureDef.bonus > bestBonus then")
    lines.append("                    local count = 1")
    lines.append("                    if C_Container and C_Container.GetContainerItemInfo then")
    lines.append("                        local info = C_Container.GetContainerItemInfo(bag, slot)")
    lines.append("                        if info and info.stackCount then count = info.stackCount end")
    lines.append("                    elseif _G.GetContainerItemInfo then")
    lines.append("                        local _, c = _G.GetContainerItemInfo(bag, slot)")
    lines.append("                        if c and c > 0 then count = c end")
    lines.append("                    end")
    lines.append("                    bestItemID = itemID")
    lines.append("                    bestName = lureDef.name")
    lines.append("                    bestBonus = lureDef.bonus")
    lines.append("                    bestSkill = lureDef.skill")
    lines.append("                    bestBag = bag")
    lines.append("                    bestSlot = slot")
    lines.append("                    bestLink = itemLink")
    lines.append("                    bestCount = count")
    lines.append("                end")
    lines.append("            end")
    lines.append("        end")
    lines.append("    end, false, true, false)")
    lines.append("")
    lines.append("    if bestItemID then")
    lines.append("        if not cachedLure then cachedLure = {} end")
    lines.append("        cachedLure.itemID = bestItemID")
    lines.append("        cachedLure.name = bestName")
    lines.append("        cachedLure.bonus = bestBonus")
    lines.append("        cachedLure.skill = bestSkill")
    lines.append("        cachedLure.bag = bestBag")
    lines.append("        cachedLure.slot = bestSlot")
    lines.append("        cachedLure.link = bestLink")
    lines.append("        cachedLure.count = bestCount")
    lines.append("    else")
    lines.append("        cachedLure = nil")
    lines.append("    end")
    lines.append("")
    lines.append("    cachedLureRank = skillRank")
    lines.append("    lureCacheDirty = false")
    lines.append("    return cachedLure")
    lines.append("end")
    lines.append("")
    lines.append("if sfui.events and sfui.events.RegisterEvent then")
    lines.append("    sfui.events.RegisterEvent(\"BAG_UPDATE_DELAYED\", D.InvalidateLureCache)")
    lines.append("    sfui.events.RegisterEvent(\"PLAYER_EQUIPMENT_CHANGED\", D.InvalidateLureCache)")
    lines.append("    sfui.events.RegisterEvent(\"SKILL_LINES_CHANGED\", D.InvalidateLureCache)")
    lines.append("end")
    lines.append("")

    content = "\n".join(lines) + "\n"

    if dry_run:
        print("[Dry-Run] Generated Lua output preview:")
        print(f"Total lines: {len(lines)}, total characters: {len(content)}")
    else:
        with open(LUA_TARGET, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Generated authoritative Lua database: {LUA_TARGET} ({len(lines)} lines)")


def print_database_summary(raw_cache: dict, zone_loot_tables: dict = None):
    """Prints status summary of current database."""
    print("\n--- SFUI Fishing Database Summary ---")
    print(f"Tracked Fish & Container Items: {len(raw_cache)}")
    print(f"Authored Waters / Zones:       {len(AUTHORITATIVE_ZONE_SKILL)}")
    if zone_loot_tables:
        print(f"Zones with Loot Drop Tables:   {len(zone_loot_tables)}")
    print(f"Classic Lures Defined:         {len(LURES)}")
    print(f"Milestone Reminders:           {len(MILESTONES)}")
    if os.path.exists(LUA_TARGET):
        sz_kb = round(os.path.getsize(LUA_TARGET) / 1024, 1)
        print(f"\n[Check] {LUA_TARGET} exists ({sz_kb} KB).")


def main():
    parser = argparse.ArgumentParser(description="SFUI Fishing Atlas & Waters Synchronizer (Camelot / Classic Forever)")
    parser.add_argument("--refresh", action="store_true", help="Force re-fetching all items from Wowhead Forever")
    parser.add_argument("--dry-run", action="store_true", help="Perform processing without writing to data/fishing_camelot.lua")
    parser.add_argument("--check", action="store_true", help="Validate and report existing database status without network calls")
    parser.add_argument("--verbose", action="store_true", help="Print detailed per-item zone catch progress")
    args = parser.parse_args()

    sync_fishing(refresh=args.refresh, dry_run=args.dry_run, verbose=args.verbose, check_only=args.check)


if __name__ == "__main__":
    main()
