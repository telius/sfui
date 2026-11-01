#!/usr/bin/env python3
"""
SFUI Fishing Atlas & Waters Synchronizer (Camelot / Classic Forever)
Automates polling zone fishing drop tables, catchable fish, containers, quest catches,
trophy fish, and item metadata from Wowhead Forever endpoints:
  - https://www.wowhead.com/forever/zone=<zoneID>  (id: 'fishing' listview)
  - https://nether.wowhead.com/forever/tooltip/item/<itemID>

Outputs:
  - data/fishing_wowhead.json (raw intermediate scrape cache for zones & species)
  - data/fishing_camelot.lua  (authoritative Lua database for SFUI on Camelot)

Usage:
    python3 scripts/sync-fishing.py [--refresh] [--dry-run] [--check] [--verbose]
"""

import argparse
import gzip
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
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
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
}

_WAF_ACQUIRED = False

# ─── Authoritative Classic & Forever Zone Mapping (Wowhead Zone ID -> UiMapID) ─
WOWHEAD_ZONE_TO_UIMAP = {
    14:    (1411, "Durotar"),
    215:   (1412, "Mulgore"),
    17:    (1413, "The Barrens"),
    36:    (1416, "Alterac Mountains"),
    45:    (1417, "Arathi Highlands"),
    3:     (1418, "Badlands"),
    4:     (1419, "Blasted Lands"),
    85:    (1420, "Tirisfal Glades"),
    130:   (1421, "Silverpine Forest"),
    28:    (1422, "Western Plaguelands"),
    139:   (1423, "Eastern Plaguelands"),
    267:   (1424, "Hillsbrad Foothills"),
    47:    (1425, "The Hinterlands"),
    1:     (1426, "Dun Morogh"),
    51:    (1427, "Searing Gorge"),
    46:    (1428, "Burning Steppes"),
    12:    (1429, "Elwynn Forest"),
    41:    (1430, "Deadwind Pass"),
    10:    (1431, "Duskwood"),
    38:    (1432, "Loch Modan"),
    44:    (1433, "Redridge Mountains"),
    33:    (1434, "Stranglethorn Vale"),
    8:     (1435, "Swamp of Sorrows"),
    40:    (1436, "Westfall"),
    11:    (1437, "Wetlands"),
    141:   (1438, "Teldrassil"),
    148:   (1439, "Darkshore"),
    331:   (1440, "Ashenvale"),
    400:   (1441, "Thousand Needles"),
    406:   (1442, "Stonetalon Mountains"),
    405:   (1443, "Desolace"),
    357:   (1444, "Feralas"),
    15:    (1445, "Dustwallow Marsh"),
    440:   (1446, "Tanaris"),
    16:    (1447, "Azshara"),
    361:   (1448, "Felwood"),
    490:   (1449, "Un'Goro Crater"),
    493:   (1450, "Moonglade"),
    1377:  (1451, "Silithus"),
    618:   (1452, "Winterspring"),
    1519:  (1453, "Stormwind City"),
    1637:  (1454, "Orgrimmar"),
    1537:  (1455, "Ironforge"),
    1638:  (1456, "Thunder Bluff"),
    1657:  (1457, "Darnassus"),
    1497:  (1458, "Undercity"),
    2597:  (1459, "Alterac Valley"),
    16593: (2521, "Zephras Isle"),
}

ZONE_NAMES = {uimap: name for _, (uimap, name) in WOWHEAD_ZONE_TO_UIMAP.items()}

# Authoritative Zone Minimum Skill Requirements (0% getaway threshold)
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
    1416: 225, # Alterac Mountains
    1417: 225, # Arathi Highlands
    1434: 225, # Stranglethorn Vale
    1435: 225, # Swamp of Sorrows
    1441: 225, # Thousand Needles
    1443: 225, # Desolace
    1445: 225, # Dustwallow Marsh

    # Tier 5 (Skill 300): High-level zones
    1419: 300, # Blasted Lands
    1422: 300, # Western Plaguelands
    1425: 300, # The Hinterlands
    1444: 300, # Feralas
    1446: 300, # Tanaris
    1447: 300, # Azshara
    1448: 300, # Felwood
    1449: 300, # Un'Goro Crater
    1450: 300, # Moonglade
    1459: 300, # Alterac Valley

    # Tier 6 (Skill 425): Maximum difficulty waters
    1423: 425, # Eastern Plaguelands
    1428: 425, # Burning Steppes
    1430: 425, # Deadwind Pass
    1451: 425, # Silithus
    1452: 425, # Winterspring
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

# Ordered trainer milestone progression
MILESTONES = [
    {
        "tier": "apprentice",
        "reqSkill": 0,
        "reqLevel": 5,
        "capBefore": 0,
        "maxRank": 75,
        "text": "learn apprentice fishing from any fishing trainer (unlocks 75 cap).",
    },
    {
        "tier": "journeyman",
        "reqSkill": 50,
        "reqLevel": 10,
        "capBefore": 75,
        "maxRank": 150,
        "text": "learn journeyman fishing from any fishing trainer at skill 50 / level 10 (unlocks 150 cap).",
    },
    {
        "tier": "expert",
        "reqSkill": 125,
        "reqLevel": 20,
        "capBefore": 150,
        "maxRank": 225,
        "text": "buy 'expert fishing - the bass and you' from old man heming in booty bay at skill 125 / level 20 (unlocks 225 cap).",
    },
    {
        "tier": "artisan",
        "reqSkill": 225,
        "reqLevel": 35,
        "capBefore": 225,
        "maxRank": 300,
        "text": "complete 'nat pagle, angler extreme' in dustwallow marsh at skill 225 / level 35 (unlocks 300 cap).",
    },
]

# Camelot Confirmed Local Overrides (for custom zones without Wowhead Forever fishing telemetry)
CAMELOT_LOCAL_OVERRIDES = {
    2521: [
        {"itemID": 6291, "share": 53.6, "kind": "f", "name": "raw brilliant smallfish"},
        {"itemID": 6289, "share": 46.4, "kind": "f", "name": "raw longjaw mud snapper"},
    ]
}

# Items that come from opening clams/trunks or non-fish pool debris
EXCLUDE_ITEM_IDS = {
    7974, 5500, 7971, 5498,  # Zesty Clam Meat & Pearls (inside clams)
    6470,                    # Deviate Scale
    20709, 21114, 21151,     # Rumsey Rum (pool drink)
    3820, 2447,              # Stranglekelp, Peacebloom
    7070, 7079, 7080,        # Elemental Water / Globe / Essence
}

QUEST_FISH_IDS = {
    19807, 19805, 19803, 19806,  # STV Fishing Extravaganza
    16967, 16968, 16969, 16970,  # Nat Pagle, Angler Extreme
    19975,                       # Zulian Mudskunk
    1467,                        # Spotted Sunfish (Redridge)
    6718, 6717,                  # Electropeller & Gaffer Jack (Stonetalon)
}

TROPHY_FISH_IDS = {
    8350,   # The 1 Ring
    19808,  # Rockhide Strongfish
}

SPECIAL_FISH_IDS = {
    6358,   # Oily Blackmouth
    6359,   # Firefin Snapper
    13422,  # Stonescale Eel
    13757,  # Lightning Eel
    13890,  # Raw Plated Armorfish
}


def classify_fished_item(it: dict) -> str | None:
    """
    Classifies a Wowhead Forever zone fishing item entry into:
      'f' = catchable fish / seafood
      'c' = fished container / trunk / chest / crate / clam / bloated fish
      'q' = quest or event fish
      't' = trophy / off-hand / rare fish
      None = non-fishing noise (potions, BoE gear from opened chests, grey trash)
    """
    iid = it.get("id")
    if not iid or iid in EXCLUDE_ITEM_IDS:
        return None

    quality = it.get("quality", 1)
    if quality == 0:
        return None

    nm = (it.get("name") or "").strip().lower()
    cl = it.get("classs")
    sb = it.get("subclass")
    slot = it.get("slot", 0)

    if iid in QUEST_FISH_IDS:
        return "q"
    if "pound " in nm or iid in TROPHY_FISH_IDS:
        return "t"
    if slot == 0 and cl in (7, 15) and any(k in nm for k in ("trunk", "chest", "crate", "bloated", "clam", "message in a bottle")):
        return "c"
    if (
        iid in SPECIAL_FISH_IDS
        or (cl == 7 and sb == 8)
        or (cl == 0 and sb in (5, 8) and any(w in nm for w in ("fish", "squid", "grouper", "salmon", "trout", "snapper", "eel", "bass", "lobster")))
    ):
        return "f"
    return None


# ─── Headless Firefox Marionette WAF Solver ──────────────────────────────────

def _m_recv(sock: socket.socket):
    buf = b""
    while b":" not in buf:
        chunk = sock.recv(64)
        if not chunk:
            return None
        buf += chunk
    length_str, rest = buf.split(b":", 1)
    length = int(length_str)
    while len(rest) < length:
        chunk = sock.recv(length - len(rest))
        if not chunk:
            break
        rest += chunk
    return json.loads(rest[:length].decode("utf-8"))


def _m_send(sock: socket.socket, msg_id: int, cmd: str, params: dict = None):
    payload = json.dumps([0, msg_id, cmd, params or {}]).encode("utf-8")
    sock.sendall(f"{len(payload)}:".encode("utf-8") + payload)
    return _m_recv(sock)


def acquire_wowhead_waf_cookie() -> bool:
    """Acquires aws-waf-token cookie using headless Firefox via Marionette."""
    global _WAF_ACQUIRED
    if _WAF_ACQUIRED:
        return True

    ff_bin = shutil.which("firefox")
    if not ff_bin:
        return False

    print("Acquiring CloudFront WAF session token via headless Firefox...")
    prof = tempfile.mkdtemp(prefix="sfui_ff_waf_")
    port = 28294
    with open(os.path.join(prof, "user.js"), "w", encoding="utf-8") as f:
        f.write(f'user_pref("marionette.port", {port});\n')

    proc = subprocess.Popen(
        [ff_bin, "--headless", "--marionette", "--profile", prof],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        sock = None
        for _ in range(30):
            try:
                sock = socket.create_connection(("127.0.0.1", port), timeout=2)
                break
            except Exception:
                time.sleep(0.2)
        if not sock:
            return False

        _m_recv(sock)
        sess = _m_send(sock, 1, "WebDriver:NewSession", {})
        ua = None
        if sess and len(sess) >= 4 and isinstance(sess[3], dict):
            caps = sess[3].get("capabilities", {})
            ua = caps.get("userAgent")

        _m_send(sock, 2, "WebDriver:Navigate", {"url": f"{WOWHEAD_BASE}/zone=14"})
        time.sleep(5)
        ck_resp = _m_send(sock, 3, "WebDriver:GetCookies", {})
        cookies = ck_resp[3] if (ck_resp and len(ck_resp) >= 4 and isinstance(ck_resp[3], list)) else []
        token = next((c.get("value") for c in cookies if c.get("name") == "aws-waf-token"), None)
        if token:
            HEADERS["Cookie"] = f"aws-waf-token={token}"
            if ua:
                HEADERS["User-Agent"] = ua
            _WAF_ACQUIRED = True
            return True
    except Exception as e:
        print(f"Warning: Failed to acquire WAF cookie via Firefox: {e}", file=sys.stderr)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
        shutil.rmtree(prof, ignore_errors=True)
    return False


def fetch_url_http(url: str, timeout: int = 12, max_retries: int = 2, allow_waf: bool = True) -> str:
    """Fetches URL via urllib with gzip decompression and automatic WAF token acquisition."""
    for attempt in range(max_retries):
        req = urllib.request.Request(url, headers=HEADERS)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                status = getattr(resp, "status", 200)
                raw = resp.read()
                enc = resp.info().get("Content-Encoding", "").lower()
                if "gzip" in enc or (len(raw) >= 2 and raw[:2] == b"\x1f\x8b"):
                    try:
                        raw = gzip.decompress(raw)
                    except Exception:
                        pass
                text = raw.decode("utf-8", errors="ignore")
                if status == 202 or "window.gokuProps" in text[:1500]:
                    if allow_waf and acquire_wowhead_waf_cookie():
                        continue
                    return ""
                return text
        except urllib.error.HTTPError as e:
            if e.code in (202, 403) and allow_waf and not _WAF_ACQUIRED:
                if acquire_wowhead_waf_cookie():
                    continue
            if attempt < max_retries - 1:
                time.sleep(0.5)
        except Exception:
            if attempt < max_retries - 1:
                time.sleep(0.5)
    return ""


def extract_zone_fishing_from_html(html: str) -> tuple[int, list]:
    """Extracts _totalCount and fishing item data list from a Wowhead Forever zone HTML page."""
    if not html:
        return 0, []

    idx = html.find("id: 'fishing'")
    if idx == -1:
        idx = html.find('id: "fishing"')
    if idx == -1:
        return 0, []

    snippet = html[idx:idx + 1000]
    m_tot = re.search(r"_totalCount:\s*(\d+)", snippet)
    total_count = int(m_tot.group(1)) if m_tot else 0

    idx_data = html.find("data:", idx)
    if idx_data == -1 or idx_data > idx + 1500:
        return total_count, []

    start = html.find("[", idx_data)
    if start == -1:
        return total_count, []

    depth = 0
    end = -1
    for i in range(start, len(html)):
        ch = html[i]
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                end = i + 1
                break

    if end == -1:
        return total_count, []

    try:
        items = json.loads(html[start:end])
        cleaned = []
        for it in items:
            cleaned.append({
                "id": int(it["id"]),
                "name": (it.get("name") or "").strip().lower(),
                "count": int(it.get("count", 0)),
                "classs": it.get("classs"),
                "subclass": it.get("subclass"),
                "quality": int(it.get("quality", 1)),
                "slot": int(it.get("slot", 0)),
            })
        return total_count, cleaned
    except Exception:
        return total_count, []


def fetch_item_metadata_nether(item_id: int) -> dict:
    """Fetches clean item name, quality, and icon from Wowhead Forever CDN."""
    url = f"{NETHER_BASE}/tooltip/item/{item_id}"
    raw = fetch_url_http(url, timeout=6, max_retries=2, allow_waf=False)
    if not raw:
        return {}
    try:
        data = json.loads(raw)
        return {
            "name": (data.get("name") or "").strip().lower(),
            "quality": int(data.get("quality", 1)),
            "icon": data.get("icon", ""),
        }
    except Exception:
        return {}


def save_cache_file(cache_data: dict):
    """Safely saves intermediate scrape cache to data/fishing_wowhead.json."""
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache_data, f, indent=2)
    except Exception as e:
        print(f"Warning: Failed to save cache: {e}", file=sys.stderr)


def sync_fishing(refresh: bool = False, dry_run: bool = False, verbose: bool = False, check_only: bool = False):
    """Main synchronization pipeline for fishing atlas and waters."""
    os.makedirs(DATA_DIR, exist_ok=True)

    # 1. Load existing cache (supports both new {"zones": ..., "species": ...} and legacy format)
    cache_data = {"zones": {}, "species": {}}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict) and "zones" in loaded and "species" in loaded:
                cache_data = loaded
            elif isinstance(loaded, dict):
                # Migrate any valid icon metadata from legacy flat item dict
                for k, v in loaded.items():
                    if isinstance(v, dict) and v.get("icon"):
                        cache_data["species"][str(k)] = {
                            "name": v.get("name", ""),
                            "kind": v.get("kind", "f"),
                            "quality": v.get("quality", 1),
                            "icon": v.get("icon", ""),
                        }
        except Exception:
            pass

    zones_cache = cache_data.setdefault("zones", {})
    species_cache = cache_data.setdefault("species", {})

    if check_only:
        zone_loot_tables, species_summary = build_tables_from_zones(zones_cache, species_cache)
        print_database_summary(species_summary, zone_loot_tables)
        return

    # 2. Poll zone fishing tables from Wowhead Forever
    cache_dirty = False
    zone_items = sorted(WOWHEAD_ZONE_TO_UIMAP.items(), key=lambda x: x[1][0])
    total_zones = len(zone_items)

    for idx, (wh_id, (uimap, zname)) in enumerate(zone_items, start=1):
        str_uimap = str(uimap)
        cached_z = zones_cache.get(str_uimap)
        needs_fetch = refresh or (cached_z is None)

        if needs_fetch:
            print(f"[{idx}/{total_zones}] Polling zone {zname} (uimap={uimap}, wh_zone={wh_id}) from Wowhead Forever...")
            html = fetch_url_http(f"{WOWHEAD_BASE}/zone={wh_id}", timeout=12, max_retries=2, allow_waf=True)
            total_count, items = extract_zone_fishing_from_html(html)
            zones_cache[str_uimap] = {
                "uimap": uimap,
                "wh_zone_id": wh_id,
                "name": zname,
                "total_count": total_count,
                "items": items,
                "fetched_at": int(time.time()),
            }
            cache_dirty = True
            save_cache_file(cache_data)
            if verbose:
                print(f"  -> total_count={total_count}, items={len(items)}")
            time.sleep(0.1)

    # 3. Classify discovered species across all zones and enrich metadata via Nether CDN
    zone_loot_tables, discovered_species = build_tables_from_zones(zones_cache, species_cache)

    for str_iid, sp_info in sorted(discovered_species.items(), key=lambda x: int(x[0])):
        iid = int(str_iid)
        existing_meta = species_cache.get(str_iid, {})
        if refresh or not existing_meta.get("icon"):
            if verbose:
                print(f"Fetching Nether tooltip metadata for item {iid} ({sp_info['name']})...")
            meta = fetch_item_metadata_nether(iid)
            if meta:
                sp_info["name"] = meta.get("name") or sp_info["name"]
                sp_info["quality"] = meta.get("quality", sp_info["quality"])
                sp_info["icon"] = meta.get("icon", "")
            cache_dirty = True
        else:
            sp_info["icon"] = existing_meta.get("icon", "")
            sp_info["quality"] = existing_meta.get("quality", sp_info["quality"])
        species_cache[str_iid] = sp_info

    if cache_dirty:
        save_cache_file(cache_data)
        print(f"Saved authoritative fishing scrape cache to {CACHE_FILE}")

    # 4. Generate data/fishing_camelot.lua
    generate_lua_database(zone_loot_tables, species_cache, dry_run=dry_run)
    print_database_summary(species_cache, zone_loot_tables)


def build_tables_from_zones(zones_cache: dict, existing_species: dict) -> tuple[dict, dict]:
    """Builds per-zone drop rate tables and discovered species index from raw zone fishing data."""
    zone_loot_tables = {}
    discovered_species = {}

    for str_uimap, zdata in sorted(zones_cache.items(), key=lambda x: int(x[0])):
        uimap = int(str_uimap)
        tot = int(zdata.get("total_count", 0))
        items = zdata.get("items", [])
        if tot <= 0 or not items:
            continue

        sum_all = sum(int(it.get("count", 0)) for it in items)
        # Use Wowhead _totalCount as denominator unless zone has partial count anomaly (e.g. Burning Steppes lava casts)
        denom = tot if (sum_all >= 0.8 * tot) else max(sum_all, 1)

        loot_list = []
        for it in items:
            kind = classify_fished_item(it)
            if not kind:
                continue

            iid = int(it["id"])
            cnt = int(it.get("count", 0))
            nm = (it.get("name") or "").strip().lower()
            q = int(it.get("quality", 1))
            share = round((cnt / denom) * 100.0, 1)

            sp_entry = discovered_species.setdefault(str(iid), {
                "name": nm,
                "kind": kind,
                "quality": q,
                "icon": existing_species.get(str(iid), {}).get("icon", ""),
                "zones": [],
            })

            if share >= 0.1:
                loot_list.append({
                    "itemID": iid,
                    "share": share,
                    "kind": kind,
                    "count": cnt,
                })
                sp_entry["zones"].append({
                    "uimap": uimap,
                    "name": zdata.get("name", "").lower(),
                    "count": cnt,
                    "outof": denom,
                    "share": share,
                })

        loot_list.sort(key=lambda x: (x["share"], x["count"]), reverse=True)
        if loot_list:
            zone_loot_tables[uimap] = [[x["itemID"], x["share"], x["kind"]] for x in loot_list]

    # Incorporate Camelot local overrides (e.g. Zephras Isle)
    for uimap, entries in CAMELOT_LOCAL_OVERRIDES.items():
        zone_loot_tables[uimap] = [[e["itemID"], e["share"], e["kind"]] for e in entries]
        for e in entries:
            str_iid = str(e["itemID"])
            sp_entry = discovered_species.setdefault(str_iid, {
                "name": e.get("name", ""),
                "kind": e["kind"],
                "quality": 1,
                "icon": existing_species.get(str_iid, {}).get("icon", ""),
                "zones": [],
            })
            sp_entry["zones"].append({
                "uimap": uimap,
                "name": ZONE_NAMES.get(uimap, "").lower(),
                "count": int(e["share"] * 10),
                "outof": 1000,
                "share": e["share"],
            })

    # Filter discovered_species to only items that appear in at least one zone loot table
    active_species = {k: v for k, v in discovered_species.items() if v.get("zones")}
    return zone_loot_tables, active_species


def generate_lua_database(zone_loot_tables: dict, species_cache: dict, dry_run: bool = False):
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

    # Milestones (ordered progression array)
    lines.append("-- Trainer milestone reminders (ordered by progression tier)")
    lines.append("D.MILESTONES = {")
    for m in MILESTONES:
        lines.append(
            f'    {{ tier = "{m["tier"]}", reqSkill = {m["reqSkill"]}, reqLevel = {m["reqLevel"]}, '
            f'capBefore = {m["capBefore"]}, maxRank = {m["maxRank"]}, text = "{m["text"]}" }},'
        )
    lines.append("}")
    lines.append("")

    # ── 3. Zone Loot Tables ──────────────────────────────────────────────────
    lines.append("-- ─── 3. Zone Loot Tables (Wowhead Forever Empirical Drop Rates) ──────────────")
    lines.append("-- Mapping: [mapID] = { { itemID, sharePercent, kind }, ... }")
    lines.append('-- kind: "f" = fish, "c" = container / trunk / chest / clam, "q" = quest, "t" = trophy')

    # Primary zones (Tier 1-3 starter, secondary, and capital city waters)
    primary_zones = [
        1411, 1412, 1413, 1420, 1421, 1424, 1426, 1429, 1431, 1432,
        1433, 1436, 1437, 1438, 1439, 1440, 1442, 1453, 1454, 1455,
        1456, 1457, 1458, 2521,
    ]
    lines.append("D.ZONE_FISH = {")
    for uimap in sorted(primary_zones):
        loot = zone_loot_tables.get(uimap)
        if loot:
            zname = ZONE_NAMES.get(uimap, f"Map {uimap}")
            entries_str = ", ".join(f'{{ {item[0]}, {item[1]}, "{item[2]}" }}' for item in loot)
            lines.append(f"    [{uimap}] = {{ {entries_str} }}, -- {zname}")
    lines.append("}")
    lines.append("")

    # Higher-level zones (Tier 4-6 waters)
    classic_zones = [k for k in AUTHORITATIVE_ZONE_SKILL.keys() if k not in primary_zones]
    lines.append("-- Higher-level zones (Level 30+) and endgame waters")
    lines.append("D.ZONE_FISH_CLASSIC = {")
    for uimap in sorted(classic_zones):
        loot = zone_loot_tables.get(uimap)
        if loot:
            zname = ZONE_NAMES.get(uimap, f"Map {uimap}")
            entries_str = ", ".join(f'{{ {item[0]}, {item[1]}, "{item[2]}" }}' for item in loot)
            lines.append(f"    [{uimap}] = {{ {entries_str} }}, -- {zname}")
    lines.append("}")
    lines.append("")

    # ── 3b. Species Fallback Names ───────────────────────────────────────────
    lines.append("-- Authoritative lowercase species names (fallback before client item cache resolves)")
    lines.append("D.SPECIES_NAMES = {")
    for str_iid in sorted(species_cache.keys(), key=lambda x: int(x)):
        sp = species_cache[str_iid]
        nm = (sp.get("name") or "").replace('"', '\\"')
        if nm:
            lines.append(f'    [{int(str_iid)}] = "{nm}",')
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
    lines.append("                        name = D.SPECIES_NAMES[itemID],")
    lines.append("                        kind = kind,")
    lines.append('                        isContainer = (kind == "c"),')
    lines.append("                        zones = {},")
    lines.append("                        minSkill = 9999,")
    lines.append("                        minSkillAny = 9999,")
    lines.append("                    }")
    lines.append("                    speciesCatalog[itemID] = item")
    lines.append("                end")
    lines.append("")
    lines.append("                local reqSkill = D.ZONE_SKILL[mapID] or 0")
    lines.append("                if reqSkill > 0 then")
    lines.append("                    if reqSkill < item.minSkillAny then")
    lines.append("                        item.minSkillAny = reqSkill")
    lines.append("                    end")
    lines.append("                    if (share or 0) >= 1.5 and reqSkill < item.minSkill then")
    lines.append("                        item.minSkill = reqSkill")
    lines.append("                    end")
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
    lines.append("        if item.minSkill == 9999 then item.minSkill = item.minSkillAny end")
    lines.append("        if item.minSkill == 9999 then item.minSkill = 0 end")
    lines.append("        item.minSkillAny = nil")
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
    lines.append("--- Returns the fallback lowercase name for a species itemID")
    lines.append("--- @param itemID number")
    lines.append("--- @return string|nil")
    lines.append("function D.GetSpeciesName(itemID)")
    lines.append("    return itemID and D.SPECIES_NAMES[itemID] or nil")
    lines.append("end")
    lines.append("")
    lines.append("--- Evaluates a milestone tier against the player's current rank, maxRank, and level")
    lines.append("--- @param m table")
    lines.append("--- @param rank number")
    lines.append("--- @param maxRank number")
    lines.append("--- @param playerLevel number|nil")
    lines.append("--- @return string state ('learned' | 'capped' | 'available' | 'level_locked' | 'locked')")
    lines.append("function D.GetMilestoneStatus(m, rank, maxRank, playerLevel)")
    lines.append("    rank = rank or 0")
    lines.append("    maxRank = maxRank or 0")
    lines.append("    if maxRank >= (m.maxRank or 0) then")
    lines.append('        return "learned"')
    lines.append("    end")
    lines.append("    if (m.capBefore or 0) > 0 and rank >= m.capBefore then")
    lines.append('        return "capped"')
    lines.append("    end")
    lines.append("    if rank >= (m.reqSkill or 0) then")
    lines.append("        if playerLevel and m.reqLevel and playerLevel < m.reqLevel then")
    lines.append('            return "level_locked"')
    lines.append("        end")
    lines.append('        return "available"')
    lines.append("    end")
    lines.append('    return "locked"')
    lines.append("end")
    lines.append("")
    lines.append("--- Returns the next actionable trainer milestone (if currently capped or available)")
    lines.append("--- @param rank number")
    lines.append("--- @param maxRank number")
    lines.append("--- @param playerLevel number|nil")
    lines.append("--- @return table|nil milestone, string|nil state")
    lines.append("function D.GetActiveMilestone(rank, maxRank, playerLevel)")
    lines.append("    for _, m in ipairs(D.MILESTONES) do")
    lines.append("        local st = D.GetMilestoneStatus(m, rank, maxRank, playerLevel)")
    lines.append('        if st == "capped" or st == "available" or st == "level_locked" then')
    lines.append("            return m, st")
    lines.append("        end")
    lines.append("    end")
    lines.append("    return nil, nil")
    lines.append("end")
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
    lines.append('    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", D.InvalidateLureCache)')
    lines.append('    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", D.InvalidateLureCache)')
    lines.append('    sfui.events.RegisterEvent("SKILL_LINES_CHANGED", D.InvalidateLureCache)')
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


def print_database_summary(species_cache: dict, zone_loot_tables: dict = None):
    """Prints status summary of current database."""
    print("\n--- SFUI Fishing Database Summary ---")
    print(f"Tracked Fish & Container Items: {len(species_cache)}")
    print(f"Authored Waters / Zones:       {len(AUTHORITATIVE_ZONE_SKILL)}")
    if zone_loot_tables is not None:
        print(f"Zones with Loot Drop Tables:   {len(zone_loot_tables)}")
    print(f"Classic Lures Defined:         {len(LURES)}")
    print(f"Milestone Reminders:           {len(MILESTONES)}")
    if os.path.exists(LUA_TARGET):
        sz_kb = round(os.path.getsize(LUA_TARGET) / 1024, 1)
        print(f"\n[Check] {LUA_TARGET} exists ({sz_kb} KB).")


def main():
    parser = argparse.ArgumentParser(description="SFUI Fishing Atlas & Waters Synchronizer (Camelot / Classic Forever)")
    parser.add_argument("--refresh", action="store_true", help="Force re-fetching all zones and items from Wowhead Forever")
    parser.add_argument("--dry-run", action="store_true", help="Perform processing without writing to data/fishing_camelot.lua")
    parser.add_argument("--check", action="store_true", help="Validate and report existing database status without network calls")
    parser.add_argument("--verbose", action="store_true", help="Print detailed per-zone catch progress")
    args = parser.parse_args()

    sync_fishing(refresh=args.refresh, dry_run=args.dry_run, verbose=args.verbose, check_only=args.check)


if __name__ == "__main__":
    main()
