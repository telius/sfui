#!/usr/bin/env python3
"""
SFUI Shared Data Synchronization Core (Camelot / Classic Forever)
Provides unified infrastructure for all SFUI data synchronizers:
  - CloudFront WAF-capable HTTP & Gzip client (with headless Firefox Marionette fallback)
  - Wowhead Forever Nether CDN item metadata fetcher
  - Shared Listview / relaxed-JSON / g_mapperData parsers
  - Automatic Wowhead Forever zone, dungeon, and raid discovery (data/forever_zones.json)
  - Atomic file writer with mandatory `luac -p` syntax verification
"""

import filecmp
import gzip
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA_DIR = os.path.join(REPO_ROOT, "data")
ZONES_CACHE_FILE = os.path.join(DATA_DIR, "forever_zones.json")

WOWHEAD_BASE = "https://www.wowhead.com/forever"
NETHER_BASE = "https://nether.wowhead.com/forever"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:159.0) Gecko/20100101 Firefox/159.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
}

_WAF_ACQUIRED = False
_WAF_ATTEMPTED = False
_WAF_LOCK = threading.Lock()

# ─── Authoritative Classic & Forever Baseline Zones ──────────────────────────
# category: 0 = Eastern Kingdoms, 1 = Kalimdor, 2 = Dungeon, 3 = Raid, 6 = Battleground
DEFAULT_FOREVER_ZONES = {
    # Open-world zones & cities (with UiMapID, Continent, and Fishing Skill threshold)
    14:    {"uimap": 1411, "name": "Durotar",               "continent": "kalimdor",         "category": 1, "fishing_skill": 25},
    215:   {"uimap": 1412, "name": "Mulgore",               "continent": "kalimdor",         "category": 1, "fishing_skill": 25},
    17:    {"uimap": 1413, "name": "The Barrens",           "continent": "kalimdor",         "category": 1, "fishing_skill": 75},
    36:    {"uimap": 1416, "name": "Alterac Mountains",     "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 225},
    45:    {"uimap": 1417, "name": "Arathi Highlands",      "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 225},
    3:     {"uimap": 1418, "name": "Badlands",              "continent": "eastern_kingdoms", "category": 0, "fishing_skill": None},
    4:     {"uimap": 1419, "name": "Blasted Lands",         "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 1},
    85:    {"uimap": 1420, "name": "Tirisfal Glades",       "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 25},
    130:   {"uimap": 1421, "name": "Silverpine Forest",     "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 75},
    28:    {"uimap": 1422, "name": "Western Plaguelands",   "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 330},
    139:   {"uimap": 1423, "name": "Eastern Plaguelands",   "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 425},
    267:   {"uimap": 1424, "name": "Hillsbrad Foothills",   "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 150},
    47:    {"uimap": 1425, "name": "The Hinterlands",       "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 330},
    1:     {"uimap": 1426, "name": "Dun Morogh",            "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 25},
    51:    {"uimap": 1427, "name": "Searing Gorge",         "continent": "eastern_kingdoms", "category": 0, "fishing_skill": None},
    46:    {"uimap": 1428, "name": "Burning Steppes",       "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 425},
    12:    {"uimap": 1429, "name": "Elwynn Forest",         "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 25},
    41:    {"uimap": 1430, "name": "Deadwind Pass",         "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 425},
    10:    {"uimap": 1431, "name": "Duskwood",              "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 150},
    38:    {"uimap": 1432, "name": "Loch Modan",            "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 75},
    44:    {"uimap": 1433, "name": "Redridge Mountains",    "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 150},
    33:    {"uimap": 1434, "name": "Stranglethorn Vale",    "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 225},
    8:     {"uimap": 1435, "name": "Swamp of Sorrows",      "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 225},
    40:    {"uimap": 1436, "name": "Westfall",              "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 75},
    11:    {"uimap": 1437, "name": "Wetlands",              "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 150},
    141:   {"uimap": 1438, "name": "Teldrassil",            "continent": "kalimdor",         "category": 1, "fishing_skill": 25},
    148:   {"uimap": 1439, "name": "Darkshore",             "continent": "kalimdor",         "category": 1, "fishing_skill": 75},
    331:   {"uimap": 1440, "name": "Ashenvale",             "continent": "kalimdor",         "category": 1, "fishing_skill": 150},
    400:   {"uimap": 1441, "name": "Thousand Needles",      "continent": "kalimdor",         "category": 1, "fishing_skill": 225},
    406:   {"uimap": 1442, "name": "Stonetalon Mountains",  "continent": "kalimdor",         "category": 1, "fishing_skill": 150},
    405:   {"uimap": 1443, "name": "Desolace",              "continent": "kalimdor",         "category": 1, "fishing_skill": 225},
    357:   {"uimap": 1444, "name": "Feralas",               "continent": "kalimdor",         "category": 1, "fishing_skill": 330},
    15:    {"uimap": 1445, "name": "Dustwallow Marsh",      "continent": "kalimdor",         "category": 1, "fishing_skill": 225},
    440:   {"uimap": 1446, "name": "Tanaris",               "continent": "kalimdor",         "category": 1, "fishing_skill": 330},
    16:    {"uimap": 1447, "name": "Azshara",               "continent": "kalimdor",         "category": 1, "fishing_skill": 330},
    361:   {"uimap": 1448, "name": "Felwood",               "continent": "kalimdor",         "category": 1, "fishing_skill": 330},
    490:   {"uimap": 1449, "name": "Un'Goro Crater",        "continent": "kalimdor",         "category": 1, "fishing_skill": 330},
    493:   {"uimap": 1450, "name": "Moonglade",             "continent": "kalimdor",         "category": 1, "fishing_skill": 330},
    1377:  {"uimap": 1451, "name": "Silithus",              "continent": "kalimdor",         "category": 1, "fishing_skill": 425},
    618:   {"uimap": 1452, "name": "Winterspring",          "continent": "kalimdor",         "category": 1, "fishing_skill": 425},
    1519:  {"uimap": 1453, "name": "Stormwind City",        "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 75},
    1637:  {"uimap": 1454, "name": "Orgrimmar",             "continent": "kalimdor",         "category": 1, "fishing_skill": 75},
    1537:  {"uimap": 1455, "name": "Ironforge",             "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 75},
    1638:  {"uimap": 1456, "name": "Thunder Bluff",         "continent": "kalimdor",         "category": 1, "fishing_skill": 75},
    1657:  {"uimap": 1457, "name": "Darnassus",             "continent": "kalimdor",         "category": 1, "fishing_skill": 75},
    1497:  {"uimap": 1458, "name": "Undercity",             "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 75},
    2597:  {"uimap": 1459, "name": "Alterac Valley",        "continent": "eastern_kingdoms", "category": 6, "fishing_skill": 330},
    # Custom Warcraft Forever / Camelot Zones & Dungeons
    616:   {"uimap": 2482,   "name": "Mount Hyjal",               "continent": "kalimdor",         "category": 1, "fishing_skill": 425},
    16593: {"uimap": 2521,   "name": "Zephras Isle",              "continent": "kalimdor",         "category": 1, "fishing_skill": 25},
    16591: {"uimap": 2548,   "name": "Riverglades",               "continent": "eastern_kingdoms", "category": 0, "fishing_skill": 225},
    16651: {"uimap": 2652,   "name": "Shen'dralas",               "continent": "kalimdor",         "category": 1, "fishing_skill": 300},
    16919: {"uimap": 116919, "name": "Hall of Thanes",            "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    16611: {"uimap": 116611, "name": "Ruins of Lordaeron",        "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    16732: {"uimap": 116732, "name": "Excavation Site: Wetlands", "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    16544: {"uimap": 116544, "name": "City of Dalaran",           "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None, "alt_wh_ids": [16560]},
    # Classic Dungeons & Raids (with synthetic mapIDs 100000 + wh_id and fishing_skill for fishable instances)
    2437:  {"uimap": 102437, "name": "Ragefire Chasm",            "continent": "kalimdor",         "category": 2, "fishing_skill": None},
    718:   {"uimap": 100718, "name": "Wailing Caverns",           "continent": "kalimdor",         "category": 2, "fishing_skill": 25},
    1581:  {"uimap": 101581, "name": "The Deadmines",             "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    209:   {"uimap": 100209, "name": "Shadowfang Keep",           "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    719:   {"uimap": 100719, "name": "Blackfathom Deeps",         "continent": "kalimdor",         "category": 2, "fishing_skill": 75},
    717:   {"uimap": 100717, "name": "The Stockade",              "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    721:   {"uimap": 100721, "name": "Gnomeregan",                "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    491:   {"uimap": 100491, "name": "Razorfen Kraul",            "continent": "kalimdor",         "category": 2, "fishing_skill": None},
    796:   {"uimap": 100796, "name": "Scarlet Monastery",         "continent": "eastern_kingdoms", "category": 2, "fishing_skill": 150},
    722:   {"uimap": 100722, "name": "Razorfen Downs",            "continent": "kalimdor",         "category": 2, "fishing_skill": None},
    1337:  {"uimap": 101337, "name": "Uldaman",                   "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    1176:  {"uimap": 101176, "name": "Zul'Farrak",                "continent": "kalimdor",         "category": 2, "fishing_skill": None},
    2100:  {"uimap": 102100, "name": "Maraudon",                  "continent": "kalimdor",         "category": 2, "fishing_skill": 205},
    1477:  {"uimap": 101477, "name": "Sunken Temple",             "continent": "eastern_kingdoms", "category": 2, "fishing_skill": 205},
    1584:  {"uimap": 101584, "name": "Blackrock Depths",          "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    1583:  {"uimap": 101583, "name": "Blackrock Spire",           "continent": "eastern_kingdoms", "category": 2, "fishing_skill": None},
    2557:  {"uimap": 102557, "name": "Dire Maul",                 "continent": "kalimdor",         "category": 2, "fishing_skill": 330},
    2057:  {"uimap": 102057, "name": "Scholomance",               "continent": "eastern_kingdoms", "category": 2, "fishing_skill": 330},
    2017:  {"uimap": 102017, "name": "Stratholme",                "continent": "eastern_kingdoms", "category": 2, "fishing_skill": 330},
    1977:  {"uimap": 101977, "name": "Zul'Gurub",                 "continent": "eastern_kingdoms", "category": 3, "fishing_skill": 330},
    2717:  {"uimap": 102717, "name": "Molten Core",               "continent": "eastern_kingdoms", "category": 3, "fishing_skill": None},
    2677:  {"uimap": 102677, "name": "Blackwing Lair",            "continent": "eastern_kingdoms", "category": 3, "fishing_skill": None},
    3429:  {"uimap": 103429, "name": "Ruins of Ahn'Qiraj",        "continent": "kalimdor",         "category": 3, "fishing_skill": None},
    3428:  {"uimap": 103428, "name": "Temple of Ahn'Qiraj",       "continent": "kalimdor",         "category": 3, "fishing_skill": None},
    3456:  {"uimap": 103456, "name": "Naxxramas",                 "continent": "eastern_kingdoms", "category": 3, "fishing_skill": None},
}


# ─── Headless Firefox Marionette CloudFront WAF Solver ───────────────────────

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


_WAF_CACHE_FILE = os.path.join(tempfile.gettempdir(), "sfui_wowhead_waf.json")
_LAST_WAF_TS = 0.0
_RATE_LOCK = threading.Lock()
_LAST_REQ_TS = 0.0
_MIN_WOWHEAD_INTERVAL = 0.35


def _load_cached_waf_cookie() -> bool:
    global _WAF_ACQUIRED, _LAST_WAF_TS
    if not os.path.exists(_WAF_CACHE_FILE):
        return False
    try:
        with open(_WAF_CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        ts = float(data.get("ts") or 0)
        if time.time() - ts < 3600 and data.get("token") and data.get("ua"):
            HEADERS["Cookie"] = f"aws-waf-token={data['token']}"
            HEADERS["User-Agent"] = data["ua"]
            _WAF_ACQUIRED = True
            _LAST_WAF_TS = ts
            return True
    except Exception:
        pass
    return False


_load_cached_waf_cookie()


def acquire_wowhead_waf_cookie(force: bool = False) -> bool:
    """Acquires aws-waf-token cookie using headless Firefox via Marionette (thread-safe & cached across subprocesses)."""
    global _WAF_ACQUIRED, _WAF_ATTEMPTED, _LAST_WAF_TS
    with _WAF_LOCK:
        if _WAF_ACQUIRED and not force:
            return True
        if not force and _load_cached_waf_cookie():
            return True
        if _WAF_ATTEMPTED and not force:
            return False
        _WAF_ATTEMPTED = True

        ff_bin = shutil.which("firefox")
        if not ff_bin:
            return False

        print("Acquiring CloudFront WAF session token via headless Firefox...")
        prof = tempfile.mkdtemp(prefix="sfui_ff_waf_")
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s_port:
            s_port.bind(("127.0.0.1", 0))
            port = s_port.getsockname()[1]

        with open(os.path.join(prof, "user.js"), "w", encoding="utf-8") as f:
            f.write(f'user_pref("marionette.port", {port});\n')

        proc = subprocess.Popen(
            [ff_bin, "--no-remote", "--headless", "--marionette", "--profile", prof],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            sock = None
            for _ in range(30):
                try:
                    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                    break
                except Exception:
                    time.sleep(0.2)
            if not sock:
                return False

            _m_recv(sock)
            sess = _m_send(sock, 1, "WebDriver:NewSession", {})
            ua = None
            if sess and len(sess) >= 4 and isinstance(sess[3], dict):
                ua = (sess[3].get("capabilities") or {}).get("userAgent")

            _m_send(sock, 2, "WebDriver:Navigate", {"url": f"{WOWHEAD_BASE}/zone=14"})

            token = None
            for step in range(10):
                time.sleep(1.0)
                ck_resp = _m_send(sock, 3 + step * 2, "WebDriver:GetCookies", {})
                cookies = ck_resp[3] if (ck_resp and len(ck_resp) >= 4 and isinstance(ck_resp[3], list)) else []
                token = next((c.get("value") for c in cookies if c.get("name") == "aws-waf-token"), None)
                if token:
                    break
                if step == 1:
                    t_resp = _m_send(sock, 4 + step * 2, "WebDriver:GetTitle", {})
                    title_val = (t_resp[3].get("value") or "") if (t_resp and len(t_resp) >= 4 and isinstance(t_resp[3], dict)) else ""
                    if "The request could not be satisfied" in title_val:
                        print("Warning: CloudFront temporary rate-limit active; waiting for cooldown...", file=sys.stderr)
                        break
            if token:
                HEADERS["Cookie"] = f"aws-waf-token={token}"
                if ua:
                    HEADERS["User-Agent"] = ua
                _WAF_ACQUIRED = True
                _LAST_WAF_TS = time.time()
                try:
                    with open(_WAF_CACHE_FILE, "w", encoding="utf-8") as wf:
                        json.dump({"token": token, "ua": ua, "ts": _LAST_WAF_TS}, wf)
                except Exception:
                    pass
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


def _pace_wowhead_request(url: str):
    """Paces requests to www.wowhead.com so burst scraping never trips CloudFront's rate-based IP block."""
    global _LAST_REQ_TS
    if "www.wowhead.com" not in url:
        return
    with _RATE_LOCK:
        now = time.time()
        wait = _MIN_WOWHEAD_INTERVAL - (now - _LAST_REQ_TS)
        if wait > 0:
            time.sleep(wait)
        _LAST_REQ_TS = time.time()


def fetch_url(url: str, timeout: int = 12, max_retries: int = 2, allow_waf: bool = True) -> str:
    """Fetches URL via urllib with gzip decompression, request pacing, and automatic CloudFront WAF token acquisition."""
    waf_refreshed = False
    for attempt in range(max_retries + 1):
        _pace_wowhead_request(url)
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
                    if allow_waf and not waf_refreshed:
                        waf_refreshed = True
                        if acquire_wowhead_waf_cookie(force=True):
                            continue
                    return ""
                return text
        except urllib.error.HTTPError as e:
            is_waf_challenge = (e.code == 202) or (e.code == 403 and ("x-amzn-waf-action" in e.headers or not _WAF_ACQUIRED))
            if is_waf_challenge and allow_waf and not waf_refreshed:
                waf_refreshed = True
                if acquire_wowhead_waf_cookie(force=True):
                    continue
            if attempt < max_retries:
                time.sleep(0.5)
        except Exception:
            if attempt < max_retries:
                time.sleep(0.5)
    return ""


def fetch_item_metadata_nether(item_id: int) -> dict:
    """Fetches clean item name, quality, and icon from Wowhead Forever Nether CDN."""
    url = f"{NETHER_BASE}/tooltip/item/{item_id}"
    raw = fetch_url(url, timeout=6, max_retries=2, allow_waf=False)
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


# ─── Shared Parsers (Relaxed JSON, Listview, Mapper) ─────────────────────────

def parse_relaxed_json(raw: str):
    """Parses relaxed JavaScript object literal syntax returned in Wowhead variables."""
    fixed = re.sub(r'([,{]\s*)([a-zA-Z0-9_]+)\s*:', r'\1"\2":', raw)
    fixed = re.sub(r',\s*([}\]])', r'\1', fixed)
    return json.loads(fixed)


def extract_bracketed_array(html: str, start_search_idx: int) -> str | None:
    """Finds the first '[' at or after start_search_idx and returns the balanced '[...]' substring."""
    start = html.find("[", start_search_idx)
    if start == -1:
        return None
    depth = 0
    in_str = False
    str_char = ""
    escape = False
    for i in range(start, len(html)):
        ch = html[i]
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if in_str:
            if ch == str_char:
                in_str = False
            continue
        if ch in ('"', "'"):
            in_str = True
            str_char = ch
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return html[start:i + 1]
    return None


def extract_listview_data(html: str, listview_ids: tuple | list | str) -> tuple[int, list]:
    """
    Extracts (_totalCount, items_list) from a Wowhead page.
    Supports:
      1) Modern `<script type="application/json" id="data.page.listPage.listviews">` blocks
      2) `new Listview({ id: '...' })` blocks (strict JSON or relaxed JS object keys)
      3) `var listview<id> = [...]` globals
    """
    if not html:
        return 0, []
    if isinstance(listview_ids, str):
        listview_ids = (listview_ids,)

    # 1. Check modern JSON script tags (e.g. /forever/zones)
    for m_json in re.finditer(r'id="data\.page\.[^"]*listviews[^"]*">\s*(\[.*?\])\s*</script>', html, re.DOTALL):
        try:
            lvs = json.loads(m_json.group(1))
            for lv in lvs:
                if isinstance(lv, dict) and lv.get("id") in listview_ids:
                    data = lv.get("data") or []
                    tot = int(lv.get("_totalCount") or len(data))
                    return tot, data
        except Exception:
            pass

    # 2. Check `var listview<id> = [...]` globals
    for lid in listview_ids:
        m_var = re.search(rf"var\s+listview{re.escape(lid)}\s*=\s*(\[.*?\]);", html, re.DOTALL)
        if m_var:
            try:
                data = parse_relaxed_json(m_var.group(1))
                return len(data), data
            except Exception:
                pass

    # 3. Check `new Listview({ id: '...' })` with inline `data: [...]`
    idx = -1
    for lid in listview_ids:
        for pat in (f"id: '{lid}'", f'id: "{lid}"', f"id:'{lid}'", f'id:"{lid}"'):
            idx = html.find(pat)
            if idx != -1:
                break
        if idx != -1:
            break
    if idx != -1:
        snippet = html[idx:idx + 1500]
        m_tot = re.search(r"_totalCount:\s*(\d+)", snippet)
        total_count = int(m_tot.group(1)) if m_tot else 0

        idx_data = html.find("data:", idx)
        if idx_data != -1 and idx_data <= idx + 2000 and re.match(r"data\s*:\s*\[", html[idx_data:idx_data + 30]):
            arr_str = extract_bracketed_array(html, idx_data)
            if arr_str:
                try:
                    data = json.loads(arr_str)
                    return (total_count or len(data)), data
                except Exception:
                    try:
                        data = parse_relaxed_json(arr_str)
                        return (total_count or len(data)), data
                    except Exception:
                        pass

    return 0, []


# ─── Automatic Forever Zone, Dungeon & Raid Discovery ────────────────────────

def estimate_fishing_skill_from_level(min_level: int) -> int:
    """Estimates baseline fishing skill threshold (25..425) for a newly discovered zone from its minimum level."""
    if not min_level or min_level <= 10:
        return 25
    if min_level <= 20:
        return 75
    if min_level < 30:
        return 150
    if min_level < 40:
        return 225
    if min_level <= 50:
        return 300
    return 425


_KALIMDOR_REPS = {69, 76, 81, 530, 576, 609}
_EK_REPS = {47, 54, 68, 72, 529}


def resolve_zone_uimap_from_wowhead(
    wh_zone_id: int,
    cat: int | None = None,
    min_lvl: int = 0,
    max_lvl: int = 0,
) -> tuple[int | None, str | None, int, int, str | None, bool, bool]:
    """
    Queries `/forever/zone=<wh_zone_id>` (and up to 5 resident NPCs' `g_mapperData[str(wh_zone_id)]`)
    to resolve:
      - `uimap` (exact client UiMapID for outdoor zones, or `100000 + wh_zone_id` for instances)
      - `z_name` (clean zone title)
      - `min_lvl`, `max_lvl` (inferred from resident combat mobs or quests if `min_lvl == 0`)
      - `inferred_continent` ('kalimdor' or 'eastern_kingdoms' from quest faction reputations)
      - `has_fishing` (whether `/forever/zone=<wh_zone_id>` has a `fishing` listview)
      - `has_forever_content` (True for Classic zones < 15000, or if zone has custom Forever NPCs >= 240000, quests >= 90000, guides, or fishing)
    """
    html = fetch_url(f"{WOWHEAD_BASE}/zone={wh_zone_id}", timeout=10, max_retries=2)
    if not html:
        uimap = (100000 + int(wh_zone_id)) if cat in (2, 3) else None
        return uimap, None, min_lvl, max_lvl, None, False, (wh_zone_id < 15000)

    z_name = None
    m_title = re.search(r"<title>(.*?)\s*-\s*Zone", html, re.I)
    if m_title:
        z_name = m_title.group(1).strip()

    _, npcs = extract_listview_data(html, "npcs")
    _, quests = extract_listview_data(html, "quests")
    _, guides = extract_listview_data(html, "guides")
    tot_fish, fish_items = extract_listview_data(html, "fishing")
    has_fishing = bool(tot_fish > 0 or fish_items)
    has_forever_content = (
        wh_zone_id < 15000
        or any(int(n.get("id") or 0) >= 240000 for n in npcs)
        or any(int(q.get("id") or 0) >= 90000 for q in quests)
        or bool(guides)
        or has_fishing
    )
    if not has_forever_content:
        return None, z_name, min_lvl, max_lvl, None, False, False

    if min_lvl == 0:
        mobs = sorted([
            int(n.get("minlevel") or 0)
            for n in npcs
            if n.get("type") != 8 and n.get("react") != [1, 1] and 1 < int(n.get("minlevel") or 0) <= 62
        ])
        qlvls = sorted([
            int(q.get("level") or q.get("reqlevel") or 0)
            for q in quests
            if (q.get("_type") == 1 or q.get("category") == wh_zone_id) and int(q.get("level") or q.get("reqlevel") or 0) > 0
        ])
        if mobs:
            min_lvl = mobs[int(len(mobs) * 0.2)]
            max_lvl = mobs[int(len(mobs) * 0.85)]
        elif qlvls:
            min_lvl = max(1, min(qlvls) - 2)
            max_lvl = max(qlvls) + 2

    inferred_continent = None
    if cat not in (0, 1):
        kal_score, ek_score = 0, 0
        for q in quests:
            for rep in (q.get("reprewards") or []):
                if rep and rep[0] in _KALIMDOR_REPS:
                    kal_score += 1
                elif rep and rep[0] in _EK_REPS:
                    ek_score += 1
        if kal_score > ek_score:
            inferred_continent = "kalimdor"
        elif ek_score > kal_score:
            inferred_continent = "eastern_kingdoms"

    uimap = None
    if cat in (2, 3):
        uimap = 100000 + int(wh_zone_id)
    elif cat != 6:
        m_map = re.search(r'"uiMapId"\s*:\s*(\d+)', html)
        if m_map:
            uimap = int(m_map.group(1))
        if not uimap and npcs:
            single_zone_npcs = [n for n in npcs if len(n.get("location") or []) == 1]
            candidates = single_zone_npcs[:2] + [n for n in npcs[:2] if n not in single_zone_npcs[:2]]
            for n in candidates[:2]:
                nid = n.get("id")
                if not nid:
                    continue
                nh = fetch_url(f"{WOWHEAD_BASE}/npc={nid}", timeout=8, max_retries=2)
                m_gm = re.search(r"g_mapperData\s*=\s*(\{.*?\});", nh)
                if m_gm:
                    try:
                        gm = json.loads(m_gm.group(1))
                        pts = gm.get(str(wh_zone_id))
                        if pts and len(pts) > 0 and pts[0].get("uiMapId"):
                            uimap = int(pts[0]["uiMapId"])
                            break
                    except Exception:
                        pass

    return uimap, z_name, min_lvl, max_lvl, inferred_continent, has_fishing, has_forever_content


def load_forever_zones(refresh: bool = False, verbose: bool = False) -> dict:
    """
    Loads authoritative Wowhead Forever zone registry (`str(wh_zone_id) -> dict`),
    combining baseline `DEFAULT_FOREVER_ZONES` with `data/forever_zones.json`.
    When `refresh=True`, scrapes `https://www.wowhead.com/forever/zones` to auto-discover
    any newly added Forever open-world zones, dungeons, raids, or battlegrounds.
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    zones = {str(k): dict(v, wh_id=int(k)) for k, v in DEFAULT_FOREVER_ZONES.items()}

    if os.path.exists(ZONES_CACHE_FILE):
        try:
            with open(ZONES_CACHE_FILE, "r", encoding="utf-8") as f:
                cached = json.load(f)
            if isinstance(cached, dict):
                for k, v in cached.items():
                    if k in zones:
                        # Preserve authoritative baseline fields while keeping newly resolved uimap
                        merged = dict(v)
                        for bk, bv in zones[k].items():
                            if bv is not None:
                                merged[bk] = bv
                        zones[k] = merged
                    else:
                        zones[k] = v
        except Exception:
            pass

    if refresh:
        if verbose:
            print("Polling https://www.wowhead.com/forever/zones for newly added Forever zones/dungeons...")
        html = fetch_url(f"{WOWHEAD_BASE}/zones", timeout=12, max_retries=2)
        if html:
            _, raw_zones = extract_listview_data(html, "zones")
            name_to_key = {}
            for k, v in zones.items():
                nm = (v.get("name") or "").strip().lower()
                if nm:
                    name_to_key[nm] = k
                    name_to_key[re.sub(r"^the\s+", "", nm)] = k
            pending_alts_by_name: dict[str, list[int]] = {}
            ignore_keywords = ("test map", "test dungeon", "unused", "prototype", "crafting", "the great sea", "reuse", "programmer")
            ignore_zids = {25, 457, 1397, 1941, 2159, 2257, 3277, 3358}

            new_discovered = 0
            for z in raw_zones:
                zid = z.get("id")
                if not zid:
                    continue
                zid_int = int(zid)
                if zid_int in ignore_zids or (15000 <= zid_int < 16500):
                    continue
                str_zid = str(zid_int)
                if str_zid in zones:
                    continue

                zname = (z.get("name") or "").strip()
                zname_low = zname.lower()
                zname_norm = re.sub(r"^the\s+", "", zname_low)
                if not zname or any(kw in zname_low for kw in ignore_keywords):
                    continue
                # If a custom Forever zone shares a name with another custom Forever zone (e.g. City of Dalaran 16544 & 16560),
                # attach it as an alternate Wowhead zone ID rather than dropping it.
                matched_key = name_to_key.get(zname_low) or name_to_key.get(zname_norm)
                if matched_key:
                    if int(matched_key) >= 15000 and int(zid) >= 15000:
                        alts = zones[matched_key].setdefault("alt_wh_ids", [])
                        if int(zid) not in alts:
                            alts.append(int(zid))
                    continue

                cat = z.get("category")
                inst_type = int(z.get("instance") or 0)
                min_lvl = int(z.get("minlevel") or 0)
                max_lvl = int(z.get("maxlevel") or 0)
                continent = "eastern_kingdoms" if cat == 0 else ("kalimdor" if cat == 1 else None)

                uimap, resolved_name, min_lvl, max_lvl, inf_cont, has_fishing, has_forever_content = resolve_zone_uimap_from_wowhead(
                    int(zid), cat=cat, min_lvl=min_lvl, max_lvl=max_lvl
                )
                if not has_forever_content:
                    if int(zid) >= 15000:
                        pending_alts_by_name.setdefault(zname_norm, []).append(int(zid))
                    continue
                if resolved_name and not zname:
                    zname = resolved_name
                if not continent:
                    continent = inf_cont or "eastern_kingdoms"

                fishing_skill = None
                if cat in (0, 1) or (cat == -1 and inst_type == 0):
                    if uimap and (min_lvl > 0 or has_fishing):
                        fishing_skill = estimate_fishing_skill_from_level(min_lvl or 1)
                elif cat in (2, 3) and has_fishing:
                    fishing_skill = estimate_fishing_skill_from_level(min_lvl or 15)

                entry_dict = {
                    "wh_id": int(zid),
                    "uimap": uimap,
                    "name": zname or f"Zone {zid}",
                    "continent": continent,
                    "category": 0 if (cat == -1 and inst_type == 0) else cat,
                    "minlevel": min_lvl,
                    "maxlevel": max_lvl,
                    "fishing_skill": fishing_skill,
                    "auto_discovered": True,
                }
                if zname_norm in pending_alts_by_name:
                    entry_dict["alt_wh_ids"] = pending_alts_by_name.pop(zname_norm)
                zones[str_zid] = entry_dict
                name_to_key[zname.lower()] = str_zid
                name_to_key[zname_norm] = str_zid
                new_discovered += 1
                if verbose:
                    print(f"  [Auto-Discovered Zone] wh_id={zid} name='{zname}' cat={cat} uimap={uimap} lvl={min_lvl}-{max_lvl} cont={continent} fish={fishing_skill}")

            if new_discovered > 0:
                print(f"Discovered {new_discovered} new Wowhead Forever zone(s)/instance(s).")

    try:
        with open(ZONES_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(zones, f, indent=2, sort_keys=True)
    except Exception:
        pass

    return zones


# ─── Atomic Lua Writer with Syntax Verification ──────────────────────────────

def write_lua_atomically(target_path: str, content: str, dry_run: bool = False) -> bool:
    """
    Writes Lua content to a temporary file, validates syntax via `luac5.1 -p` or `luac -p`,
    and atomically replaces `target_path` if valid. Returns True if file was modified.
    """
    if dry_run:
        lines_cnt = content.count("\n")
        print(f"[Dry-Run] Verified Lua output preview for {os.path.relpath(target_path, REPO_ROOT)} ({lines_cnt} lines).")
        return False

    tmp_target = target_path + ".tmp"
    with open(tmp_target, "w", encoding="utf-8") as f:
        f.write(content)

    luac_bin = shutil.which("luac5.1") or shutil.which("luac")
    if luac_bin:
        check = subprocess.run([luac_bin, "-p", tmp_target], capture_output=True, text=True)
        if check.returncode != 0:
            os.remove(tmp_target)
            raise RuntimeError(f"Generated Lua in {target_path} failed syntax check:\n{check.stderr}")

    if os.path.exists(target_path) and filecmp.cmp(tmp_target, target_path, shallow=False):
        os.remove(tmp_target)
        return False

    os.replace(tmp_target, target_path)
    return True
