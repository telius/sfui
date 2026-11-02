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
import json
import os
import sys
import time

from sync_core import (
    DATA_DIR,
    REPO_ROOT,
    WOWHEAD_BASE,
    extract_listview_data,
    fetch_item_metadata_nether,
    fetch_url,
    load_forever_zones,
    write_lua_atomically,
)

CACHE_FILE = os.path.join(DATA_DIR, "fishing_wowhead.json")
LUA_TARGET = os.path.join(DATA_DIR, "fishing_camelot.lua")

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
    616:   (2482, "Mount Hyjal"),
    16593: (2521, "Zephras Isle"),
    16591: (2548, "Riverglades"),
    16651: (2652, "Shen'dralas"),
    # Fishable Classic / Forever Dungeons & Raids (synthetic mapID = 100000 + wh_id)
    718:   (100718, "Wailing Caverns"),
    719:   (100719, "Blackfathom Deeps"),
    796:   (100796, "Scarlet Monastery"),
    1477:  (101477, "Sunken Temple"),
    1977:  (101977, "Zul'Gurub"),
    2017:  (102017, "Stratholme"),
    2057:  (102057, "Scholomance"),
    2100:  (102100, "Maraudon"),
    2557:  (102557, "Dire Maul"),
}

ZONE_NAMES = {uimap: name for _, (uimap, name) in WOWHEAD_ZONE_TO_UIMAP.items()}
ALL_INSTANCE_NAME_TO_ID = {}

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
    2548: 225, # Riverglades (Forever level 36-44 zone)

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
    2652: 300, # Shen'dralas (Forever level 41-60 zone)

    # Tier 6 (Skill 425): Maximum difficulty waters
    1423: 425, # Eastern Plaguelands
    1428: 425, # Burning Steppes
    1430: 425, # Deadwind Pass
    1451: 425, # Silithus
    1452: 425, # Winterspring
    2482: 425, # Mount Hyjal (Forever level 60 zone)

    # Fishable Dungeons & Raids
    100718: 25,  # Wailing Caverns (Deviate Fish)
    100719: 75,  # Blackfathom Deeps
    100796: 150, # Scarlet Monastery
    101477: 205, # Sunken Temple (The Temple of Atal'Hakkar)
    102100: 205, # Maraudon
    101977: 330, # Zul'Gurub (Mudskunk Waters / Gahz'ranka)
    102017: 330, # Stratholme
    102057: 330, # Scholomance
    102557: 330, # Dire Maul
}

# Sub-areas requiring higher skill than the surrounding zone
ZONE_SKILL_PARTS = {
    1434: {"skill": 300, "area": "jaguero isle"},
    1444: {"skill": 425, "area": "jademir lake"},
    1447: {"skill": 425, "area": "bay of storms / scalebeard"},
}

# Authoritative Continent Mapping per UiMapID ('eastern_kingdoms' vs 'kalimdor')
ZONE_CONTINENT = {
    # Eastern Kingdoms (UiMapID 1415)
    1416: "eastern_kingdoms",  # Alterac Mountains
    1417: "eastern_kingdoms",  # Arathi Highlands
    1418: "eastern_kingdoms",  # Badlands
    1419: "eastern_kingdoms",  # Blasted Lands
    1420: "eastern_kingdoms",  # Tirisfal Glades
    1421: "eastern_kingdoms",  # Silverpine Forest
    1422: "eastern_kingdoms",  # Western Plaguelands
    1423: "eastern_kingdoms",  # Eastern Plaguelands
    1424: "eastern_kingdoms",  # Hillsbrad Foothills
    1425: "eastern_kingdoms",  # The Hinterlands
    1426: "eastern_kingdoms",  # Dun Morogh
    1427: "eastern_kingdoms",  # Searing Gorge
    1428: "eastern_kingdoms",  # Burning Steppes
    1429: "eastern_kingdoms",  # Elwynn Forest
    1430: "eastern_kingdoms",  # Deadwind Pass
    1431: "eastern_kingdoms",  # Duskwood
    1432: "eastern_kingdoms",  # Loch Modan
    1433: "eastern_kingdoms",  # Redridge Mountains
    1434: "eastern_kingdoms",  # Stranglethorn Vale
    1435: "eastern_kingdoms",  # Swamp of Sorrows
    1436: "eastern_kingdoms",  # Westfall
    1437: "eastern_kingdoms",  # Wetlands
    1453: "eastern_kingdoms",  # Stormwind City
    1455: "eastern_kingdoms",  # Ironforge
    1458: "eastern_kingdoms",  # Undercity
    1459: "eastern_kingdoms",  # Alterac Valley
    2548: "eastern_kingdoms",  # Riverglades

    # Kalimdor (UiMapID 1414)
    1411: "kalimdor",          # Durotar
    1412: "kalimdor",          # Mulgore
    1413: "kalimdor",          # The Barrens
    1438: "kalimdor",          # Teldrassil
    1439: "kalimdor",          # Darkshore
    1440: "kalimdor",          # Ashenvale
    1441: "kalimdor",          # Thousand Needles
    1442: "kalimdor",          # Stonetalon Mountains
    1443: "kalimdor",          # Desolace
    1444: "kalimdor",          # Feralas
    1445: "kalimdor",          # Dustwallow Marsh
    1446: "kalimdor",          # Tanaris
    1447: "kalimdor",          # Azshara
    1448: "kalimdor",          # Felwood
    1449: "kalimdor",          # Un'Goro Crater
    1450: "kalimdor",          # Moonglade
    1451: "kalimdor",          # Silithus
    1452: "kalimdor",          # Winterspring
    1454: "kalimdor",          # Orgrimmar
    1456: "kalimdor",          # Thunder Bluff
    1457: "kalimdor",          # Darnassus
    2482: "kalimdor",          # Mount Hyjal
    2521: "kalimdor",          # Zephras Isle
    2652: "kalimdor",          # Shen'dralas

    # Fishable Dungeons & Raids
    100796: "eastern_kingdoms", # Scarlet Monastery
    101477: "eastern_kingdoms", # Sunken Temple
    101977: "eastern_kingdoms", # Zul'Gurub
    102017: "eastern_kingdoms", # Stratholme
    102057: "eastern_kingdoms", # Scholomance
    100718: "kalimdor",         # Wailing Caverns
    100719: "kalimdor",         # Blackfathom Deeps
    102100: "kalimdor",         # Maraudon
    102557: "kalimdor",         # Dire Maul
}

# Zones that contain both Coastal (Ocean) and Inland (Lake/River/Oasis) waters
MIXED_ZONES = [
    1411,  # Durotar (Southfury River vs Echo Isles / Coast)
    1413,  # The Barrens (Oases / Southfury River vs Ratchet / Merchant Coast)
    1417,  # Arathi Highlands (Dalson's / Boulderfist vs Faldir's Cove)
    1421,  # Silverpine Forest (Lordamere Lake vs Dawning Isles Coast)
    1424,  # Hillsbrad Foothills (Darrowmere River vs Southshore Coast)
    1425,  # The Hinterlands (Valorwind Lake vs Revantusk / Overlook Coast)
    1434,  # Stranglethorn Vale (Lake Nazferiti / River vs Savage Coast / Booty Bay / Jaguero Isle)
    1435,  # Swamp of Sorrows (Inland Marsh vs Misty Reed Strand)
    1436,  # Westfall (Inland Streams vs Longshore / Gold Coast)
    1437,  # Wetlands (Inland Marsh/River vs Menethil Harbor / Coast)
    1438,  # Teldrassil (Inland Ponds/Wells vs Rut'theran Village)
    1439,  # Darkshore (Cliffspring River vs Auberdine Coast)
    1440,  # Ashenvale (Mystral Lake / Falfarren River vs Zoram Strand)
    1443,  # Desolace (Inland Ponds vs Sar'theris Strand / Shadowprey)
    1444,  # Feralas (Verdantis River / Jademir Lake vs Feathermoon / Forgotten Coast)
    1445,  # Dustwallow Marsh (Inland Marsh vs Theramore / Alcaz Coast)
    1447,  # Azshara (Lake Mennar vs Azshara Coast / Bay of Storms)
    2521,  # Zephras Isle (Shen'dar / Inland Streams vs Valanaar / Island Coast)
    2548,  # Riverglades (Meadowsbrook / Turner's Mill River vs Powderfuse Port Coast)
]

# Authoritative Water Habitat per Species ('coastal' = ocean/saltwater, 'inland' = lake/river/pond, 'oasis' = Barrens oasis)
SPECIES_HABITAT = {
    # Coastal / Ocean (Saltwater)
    4603:  "coastal",  # raw spotted yellowtail
    6303:  "coastal",  # raw slitherskin mackerel
    6358:  "coastal",  # oily blackmouth
    6359:  "coastal",  # firefin snapper
    6361:  "coastal",  # raw rainbow fin albacore
    6362:  "coastal",  # raw rockscale cod
    7973:  "coastal",  # big-mouth clam
    12238: "coastal",  # darkshore grouper
    13422: "coastal",  # stonescale eel
    13754: "coastal",  # raw glossy mightfish
    13755: "coastal",  # raw winter squid
    13756: "coastal",  # raw summer bass
    13876: "coastal",  # 40 pound yellowtail
    13877: "coastal",  # 47 pound yellowtail
    13888: "coastal",  # darkclaw lobster
    13893: "coastal",  # large raw mightfish
    13907: "coastal",  # 7 pound lobster
    13908: "coastal",  # 9 pound lobster
    13909: "coastal",  # 12 pound lobster
    16968: "coastal",  # sar'theris striker
    16969: "coastal",  # savage coast blue sailfin
    16970: "coastal",  # misty reed mahi mahi
    19807: "coastal",  # speckled tastyfish

    # Barrens Oases / Wailing Caverns
    6522:  "oasis",    # deviate fish

    # Inland Lakes, Rivers & Ponds (Freshwater)
    1467:  "inland",   # spotted sunfish
    6289:  "inland",   # raw longjaw mud snapper
    6291:  "inland",   # raw brilliant smallfish
    6292:  "inland",   # 10 pound mud snapper
    6294:  "inland",   # 12 pound mud snapper
    6295:  "inland",   # 15 pound mud snapper
    6299:  "inland",   # sickly looking fish
    6308:  "inland",   # raw bristle whisker catfish
    6309:  "inland",   # 17 pound catfish
    6310:  "inland",   # 19 pound catfish
    6311:  "inland",   # 22 pound catfish
    6317:  "inland",   # raw loch frenzy
    6458:  "inland",   # oil covered fish
    6643:  "inland",   # bloated brilliant smallfish
    6717:  "inland",   # gaffer jack
    6718:  "inland",   # electropeller
    8365:  "inland",   # raw mithril head trout
    13757: "inland",   # lightning eel
    13758: "inland",   # raw redgill
    13759: "inland",   # raw nightfin snapper
    13760: "inland",   # raw sunscale salmon
    13882: "inland",   # 42 pound redgill
    13885: "inland",   # 34 pound redgill
    13886: "inland",   # 37 pound redgill
    13889: "inland",   # raw whitescale salmon
    13890: "inland",   # raw plated armorfish
    13901: "inland",   # 15 pound salmon
    13902: "inland",   # 18 pound salmon
    16967: "inland",   # feralas ahi
    19975: "inland",   # zulian mudskunk
    21071: "inland",   # raw sagefish
    21153: "inland",   # raw greater sagefish
    251524: "inland",  # whimsyfin
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

# Default CMaNGOS / Classic Forever Tier Fishing Loot Tables (used when a newly added zone has no Wowhead fishing telemetry yet)
DEFAULT_TIER_FISHING_LOOT = {
    25: [
        {"itemID": 6291,  "share": 45.5, "kind": "f", "name": "raw brilliant smallfish"},
        {"itemID": 6289,  "share": 37.0, "kind": "f", "name": "raw longjaw mud snapper"},
        {"itemID": 6303,  "share": 17.5, "kind": "f", "name": "raw slitherskin mackerel"},
    ],
    75: [
        {"itemID": 6289,  "share": 38.0, "kind": "f", "name": "raw longjaw mud snapper"},
        {"itemID": 6308,  "share": 30.0, "kind": "f", "name": "raw bristle whisker catfish"},
        {"itemID": 6361,  "share": 18.0, "kind": "f", "name": "raw rainbow fin albacore"},
        {"itemID": 6358,  "share": 14.0, "kind": "f", "name": "oily blackmouth"},
    ],
    150: [
        {"itemID": 6308,  "share": 38.0, "kind": "f", "name": "raw bristle whisker catfish"},
        {"itemID": 8365,  "share": 32.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 6358,  "share": 14.0, "kind": "f", "name": "oily blackmouth"},
        {"itemID": 6359,  "share": 10.0, "kind": "f", "name": "firefin snapper"},
        {"itemID": 21071, "share": 6.0,  "kind": "f", "name": "raw sagefish"},
    ],
    205: [
        {"itemID": 8365,  "share": 38.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 13758, "share": 30.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 16.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 16.0, "kind": "f", "name": "raw sunscale salmon"},
    ],
    225: [
        {"itemID": 8365,  "share": 34.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 4603,  "share": 22.5, "kind": "f", "name": "raw spotted yellowtail"},
        {"itemID": 6308,  "share": 15.0, "kind": "f", "name": "raw bristle whisker catfish"},
        {"itemID": 6362,  "share": 12.0, "kind": "f", "name": "raw rockscale cod"},
        {"itemID": 21153, "share": 7.5,  "kind": "f", "name": "raw greater sagefish"},
        {"itemID": 6359,  "share": 4.5,  "kind": "f", "name": "firefin snapper"},
        {"itemID": 6358,  "share": 2.5,  "kind": "f", "name": "oily blackmouth"},
        {"itemID": 7973,  "share": 1.2,  "kind": "c", "name": "big-mouth clam"},
        {"itemID": 21228, "share": 0.8,  "kind": "c", "name": "mithril bound trunk"},
    ],
    300: [
        {"itemID": 13758, "share": 32.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 4603,  "share": 24.0, "kind": "f", "name": "raw spotted yellowtail"},
        {"itemID": 13759, "share": 16.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 16.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13422, "share": 7.0,  "kind": "f", "name": "stonescale eel"},
        {"itemID": 13754, "share": 5.0,  "kind": "f", "name": "raw glossy mightfish"},
    ],
    330: [
        {"itemID": 13758, "share": 36.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 22.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 22.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13889, "share": 15.0, "kind": "f", "name": "raw whitescale salmon"},
        {"itemID": 13757, "share": 5.0,  "kind": "f", "name": "lightning eel"},
    ],
    425: [
        {"itemID": 13889, "share": 42.5, "kind": "f", "name": "raw whitescale salmon"},
        {"itemID": 13759, "share": 21.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 19.5, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13758, "share": 12.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13757, "share": 3.8,  "kind": "f", "name": "lightning eel"},
        {"itemID": 21150, "share": 1.2,  "kind": "c", "name": "watertight trunk"},
    ],
}

# Camelot Confirmed Local Overrides (for custom zones without Wowhead Forever fishing telemetry)
CAMELOT_LOCAL_OVERRIDES = {
    2482: [
        {"itemID": 13889, "share": 42.5, "kind": "f", "name": "raw whitescale salmon"},
        {"itemID": 13759, "share": 21.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 19.5, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13758, "share": 12.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13757, "share": 3.8,  "kind": "f", "name": "lightning eel"},
        {"itemID": 21150, "share": 1.2,  "kind": "c", "name": "watertight trunk"},
    ],
    2521: [
        {"itemID": 6291,   "share": 43.0, "kind": "f", "name": "raw brilliant smallfish"},
        {"itemID": 6289,   "share": 37.0, "kind": "f", "name": "raw longjaw mud snapper"},
        {"itemID": 6303,   "share": 17.5, "kind": "f", "name": "raw slitherskin mackerel"},
        {"itemID": 251524, "share": 2.5,  "kind": "f", "name": "whimsyfin"},
    ],
    2548: [
        {"itemID": 8365,  "share": 34.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 4603,  "share": 22.5, "kind": "f", "name": "raw spotted yellowtail"},
        {"itemID": 6308,  "share": 15.0, "kind": "f", "name": "raw bristle whisker catfish"},
        {"itemID": 6362,  "share": 12.0, "kind": "f", "name": "raw rockscale cod"},
        {"itemID": 21153, "share": 7.5,  "kind": "f", "name": "raw greater sagefish"},
        {"itemID": 6359,  "share": 4.5,  "kind": "f", "name": "firefin snapper"},
        {"itemID": 6358,  "share": 2.5,  "kind": "f", "name": "oily blackmouth"},
        {"itemID": 7973,  "share": 1.2,  "kind": "c", "name": "big-mouth clam"},
        {"itemID": 21228, "share": 0.8,  "kind": "c", "name": "mithril bound trunk"},
    ],
    # Authoritative CMaNGOS Dungeon & Raid Fishing Tables
    100718: [  # Wailing Caverns
        {"itemID": 6522,  "share": 45.0, "kind": "f", "name": "deviate fish"},
        {"itemID": 6291,  "share": 25.0, "kind": "f", "name": "raw brilliant smallfish"},
        {"itemID": 6289,  "share": 20.0, "kind": "f", "name": "raw longjaw mud snapper"},
        {"itemID": 6303,  "share": 10.0, "kind": "f", "name": "raw slitherskin mackerel"},
    ],
    100719: [  # Blackfathom Deeps
        {"itemID": 6308,  "share": 38.0, "kind": "f", "name": "raw bristle whisker catfish"},
        {"itemID": 6358,  "share": 25.0, "kind": "f", "name": "oily blackmouth"},
        {"itemID": 6289,  "share": 20.0, "kind": "f", "name": "raw longjaw mud snapper"},
        {"itemID": 6361,  "share": 17.0, "kind": "f", "name": "raw rainbow fin albacore"},
    ],
    100796: [  # Scarlet Monastery
        {"itemID": 6308,  "share": 42.0, "kind": "f", "name": "raw bristle whisker catfish"},
        {"itemID": 8365,  "share": 35.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 6358,  "share": 13.0, "kind": "f", "name": "oily blackmouth"},
        {"itemID": 6359,  "share": 10.0, "kind": "f", "name": "firefin snapper"},
    ],
    101477: [  # Sunken Temple (The Temple of Atal'Hakkar)
        {"itemID": 8365,  "share": 38.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 13758, "share": 30.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 16.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 16.0, "kind": "f", "name": "raw sunscale salmon"},
    ],
    102100: [  # Maraudon
        {"itemID": 8365,  "share": 35.0, "kind": "f", "name": "raw mithril head trout"},
        {"itemID": 13758, "share": 28.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 15.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 15.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13422, "share": 7.0,  "kind": "f", "name": "stonescale eel"},
    ],
    101977: [  # Zul'Gurub
        {"itemID": 19975, "share": 25.0, "kind": "q", "name": "zulian mudskunk"},
        {"itemID": 4603,  "share": 24.0, "kind": "f", "name": "raw spotted yellowtail"},
        {"itemID": 13759, "share": 16.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 16.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13754, "share": 10.0, "kind": "f", "name": "raw glossy mightfish"},
        {"itemID": 13756, "share": 9.0,  "kind": "f", "name": "raw summer bass"},
    ],
    102017: [  # Stratholme
        {"itemID": 13758, "share": 36.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 22.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 22.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13889, "share": 15.0, "kind": "f", "name": "raw whitescale salmon"},
        {"itemID": 13757, "share": 5.0,  "kind": "f", "name": "lightning eel"},
    ],
    102057: [  # Scholomance
        {"itemID": 13758, "share": 38.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 22.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 22.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13889, "share": 18.0, "kind": "f", "name": "raw whitescale salmon"},
    ],
    102557: [  # Dire Maul
        {"itemID": 13758, "share": 38.0, "kind": "f", "name": "raw redgill"},
        {"itemID": 13759, "share": 22.0, "kind": "f", "name": "raw nightfin snapper"},
        {"itemID": 13760, "share": 22.0, "kind": "f", "name": "raw sunscale salmon"},
        {"itemID": 13889, "share": 18.0, "kind": "f", "name": "raw whitescale salmon"},
    ],
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
    19975,                       # Zulian Mudskunk (Gahz'ranka lure in Zul'Gurub)
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
    251524, # Whimsyfin
}


FISH_NAME_KEYWORDS = (
    "fish", "squid", "grouper", "salmon", "trout", "snapper", "eel", "bass",
    "lobster", "fin", "carp", "perch", "mackerel", "pike", "ray", "crab",
    "shrimp", "crawdad", "dart", "herring", "catfish", "sunfish", "flounder",
    "halibut", "tuna", "minnow", "guppy", "sturgeon", "anchovy", "sardine",
    "cod", "haddock", "bream", "darter", "scales",
)


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
        or (cl == 0 and sb in (5, 8) and any(w in nm for w in FISH_NAME_KEYWORDS))
    ):
        return "f"
    return None


def extract_zone_fishing_from_html(html: str) -> tuple[int, list]:
    """Extracts _totalCount and fishing item data list from a Wowhead Forever zone HTML page."""
    total_count, items = extract_listview_data(html, "fishing")
    cleaned = []
    for it in items:
        if not isinstance(it, dict) or "id" not in it:
            continue
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


def save_cache_file(cache_data: dict):
    """Safely saves intermediate scrape cache to data/fishing_wowhead.json."""
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache_data, f, indent=2)
    except Exception as e:
        print(f"Warning: Failed to save cache: {e}", file=sys.stderr)


def merge_discovered_zones_into_tables(forever_zones: dict):
    """Merges newly discovered Forever open-world zones and dungeons/raids into the fishing registries."""
    for _, zinfo in forever_zones.items():
        wh_id = zinfo.get("wh_id")
        uimap = zinfo.get("uimap")
        cat = zinfo.get("category")
        f_skill = zinfo.get("fishing_skill")
        if not wh_id or not uimap:
            continue
        wh_id = int(wh_id)
        uimap = int(uimap)
        zname = zinfo.get("name") or f"Zone {uimap}"
        if uimap not in ZONE_NAMES:
            ZONE_NAMES[uimap] = zname
        ALL_INSTANCE_NAME_TO_ID[zname.lower()] = uimap
        if zname.lower().startswith("the "):
            ALL_INSTANCE_NAME_TO_ID[zname.lower()[4:]] = uimap
        else:
            ALL_INSTANCE_NAME_TO_ID["the " + zname.lower()] = uimap
        if uimap not in ZONE_CONTINENT and zinfo.get("continent"):
            ZONE_CONTINENT[uimap] = zinfo.get("continent")
        if not f_skill or cat not in (0, 1, 2, 3, 6):
            continue
        if wh_id not in WOWHEAD_ZONE_TO_UIMAP:
            WOWHEAD_ZONE_TO_UIMAP[wh_id] = (uimap, zname)
        if uimap not in AUTHORITATIVE_ZONE_SKILL:
            AUTHORITATIVE_ZONE_SKILL[uimap] = int(f_skill)
        if uimap not in ZONE_CONTINENT:
            ZONE_CONTINENT[uimap] = zinfo.get("continent") or ("kalimdor" if cat == 1 else "eastern_kingdoms")
        if (
            uimap >= 2000
            and uimap < 100000
            and uimap not in MIXED_ZONES
            and any(kw in zname.lower() for kw in ("isle", "island", "coast", "bay", "strand", "glade", "river"))
        ):
            MIXED_ZONES.append(uimap)
    ALL_INSTANCE_NAME_TO_ID["the temple of atal'hakkar"] = 101477
    ALL_INSTANCE_NAME_TO_ID["temple of atal'hakkar"] = 101477


def discover_custom_forever_fish(forever_zones: dict, verbose: bool = False) -> dict[int, list[dict]]:
    """
    Scans Wowhead Forever custom Trade Goods & Consumables (id >= 240000) for newly added
    catchable Forever fish (non-crafted, fish icon or fish keyword) and maps them to their
    fished-in zones or custom Forever zones of matching skill bracket.
    Returns {uimap: [{"itemID": iid, "share": 2.5, "kind": "f", "name": nm}, ...]}.
    """
    discovered_by_uimap: dict[int, list[dict]] = {}
    search_urls = [
        f"{WOWHEAD_BASE}/items/trade-goods?filter=151;2;240000",
        f"{WOWHEAD_BASE}/items/consumables/food-and-drink?filter=151;2;240000",
    ]
    seen_ids = set()
    for url in search_urls:
        html = fetch_url(url, timeout=15, max_retries=2, allow_waf=True)
        if not html:
            continue
        _, items = extract_listview_data(html, "items")
        for it in items:
            if not isinstance(it, dict) or "id" not in it:
                continue
            iid = int(it["id"])
            if iid < 240000 or iid in seen_ids or iid in EXCLUDE_ITEM_IDS:
                continue
            seen_ids.add(iid)
            src = it.get("source") or []
            if isinstance(src, list) and 1 in src:
                continue  # Crafted item (e.g., cooked fish or potion)
            nm = (it.get("name") or "").strip().lower()
            if nm.startswith((
                "ensemble:", "craftsman's writ:", "recipe:", "plans:", "pattern:",
                "schematic:", "formula:", "manual:", "cooked ", "grilled ", "baked ",
                "smoked ", "steamed ", "fried ", "spiced ", "poached ", "seasonal ",
                "expiring ",
            )):
                continue
            cl = it.get("classs")
            sb = it.get("subclass")
            if cl == 0 and sb not in (5, 8, 0, None):
                continue
            is_fish_kw = any(w in nm for w in FISH_NAME_KEYWORDS)
            if not is_fish_kw:
                continue
            meta = fetch_item_metadata_nether(iid)
            icon = (meta.get("icon") or "").lower()
            if not icon.startswith("inv_misc_fish"):
                continue

            SPECIAL_FISH_IDS.add(iid)
            if iid not in SPECIES_HABITAT:
                SPECIES_HABITAT[iid] = "inland"

            # Check /forever/item=<iid> for explicit fished-in zones
            target_uimaps = []
            item_html = fetch_url(f"{WOWHEAD_BASE}/item={iid}", timeout=12, max_retries=2, allow_waf=True)
            if item_html:
                _, fished_in = extract_listview_data(item_html, "fished-in")
                for z in fished_in:
                    if isinstance(z, dict) and z.get("id"):
                        zid = int(z["id"])
                        if zid in WOWHEAD_ZONE_TO_UIMAP:
                            target_uimaps.append(WOWHEAD_ZONE_TO_UIMAP[zid][0])

            # Fallback: match item level to custom Forever zones of the corresponding fishing skill tier
            if not target_uimaps:
                ilvl = int(it.get("level") or 1)
                if ilvl <= 15:
                    target_skill = 25
                elif ilvl <= 25:
                    target_skill = 75
                elif ilvl <= 35:
                    target_skill = 150
                elif ilvl <= 45:
                    target_skill = 225
                elif ilvl <= 55:
                    target_skill = 300
                else:
                    target_skill = 425
                for wh_id, (uimap, _) in WOWHEAD_ZONE_TO_UIMAP.items():
                    if (wh_id >= 16000 or (2000 <= uimap < 100000)) and AUTHORITATIVE_ZONE_SKILL.get(uimap) == target_skill:
                        target_uimaps.append(uimap)

            for uimap in target_uimaps:
                discovered_by_uimap.setdefault(uimap, []).append({
                    "itemID": iid,
                    "share": 2.5,
                    "kind": "f",
                    "name": (meta.get("name") or nm).lower(),
                })
                if verbose:
                    print(f"  [Custom Fish Discovery] Mapped {nm} ({iid}) -> zone uimap={uimap}")

    return discovered_by_uimap


def sync_fishing(refresh: bool = False, dry_run: bool = False, verbose: bool = False, check_only: bool = False):
    """Main synchronization pipeline for fishing atlas and waters."""
    os.makedirs(DATA_DIR, exist_ok=True)

    # 0. Sync shared Forever zone registry (discovers any newly added Forever zones)
    forever_zones = load_forever_zones(refresh=(refresh and not check_only), verbose=verbose)
    merge_discovered_zones_into_tables(forever_zones)

    # 1. Load existing cache (supports both new {"zones": ..., "species": ...} and legacy format)
    cache_data = {"zones": {}, "species": {}}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict) and "zones" in loaded and "species" in loaded:
                cache_data = loaded
            elif isinstance(loaded, dict):
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
    custom_fish_cache = cache_data.setdefault("custom_fish_by_zone", {})

    if check_only:
        zone_loot_tables, species_summary = build_tables_from_zones(zones_cache, species_cache, custom_fish_cache)
        print_database_summary(species_summary, zone_loot_tables)
        return

    # 2. Poll zone fishing tables from Wowhead Forever
    cache_dirty = False
    if refresh or not custom_fish_cache:
        discovered_custom_fish = discover_custom_forever_fish(forever_zones, verbose=verbose)
        custom_fish_cache.clear()
        for k, v in discovered_custom_fish.items():
            custom_fish_cache[str(k)] = v
        cache_dirty = True
    else:
        for _, f_entries in custom_fish_cache.items():
            for fe in f_entries:
                iid = int(fe["itemID"])
                SPECIAL_FISH_IDS.add(iid)
                if iid not in SPECIES_HABITAT:
                    SPECIES_HABITAT[iid] = "inland"

    zone_items = sorted(WOWHEAD_ZONE_TO_UIMAP.items(), key=lambda x: x[1][0])
    total_zones = len(zone_items)

    for idx, (wh_id, (uimap, zname)) in enumerate(zone_items, start=1):
        str_uimap = str(uimap)
        cached_z = zones_cache.get(str_uimap)
        needs_fetch = refresh or (cached_z is None)

        if needs_fetch:
            print(f"[{idx}/{total_zones}] Polling zone {zname} (uimap={uimap}, wh_zone={wh_id}) from Wowhead Forever...")
            html = fetch_url(f"{WOWHEAD_BASE}/zone={wh_id}", timeout=12, max_retries=2, allow_waf=True)
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
    zone_loot_tables, discovered_species = build_tables_from_zones(zones_cache, species_cache, custom_fish_cache)

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

        # Auto-infer habitat ('inland' vs 'coastal') for any newly discovered fish not in SPECIES_HABITAT
        if iid not in SPECIES_HABITAT and sp_info.get("kind") in ("f", "q", "t"):
            drop_uimaps = [z["uimap"] for z in sp_info.get("zones", []) if z.get("uimap")]
            if drop_uimaps and all(u not in MIXED_ZONES and u != 2521 for u in drop_uimaps):
                SPECIES_HABITAT[iid] = "inland"

    if cache_dirty:
        save_cache_file(cache_data)
        print(f"Saved authoritative fishing scrape cache to {CACHE_FILE}")

    # 4. Generate data/fishing_camelot.lua
    generate_lua_database(zone_loot_tables, species_cache, dry_run=dry_run)
    print_database_summary(species_cache, zone_loot_tables)


def build_tables_from_zones(zones_cache: dict, existing_species: dict, custom_fish_cache: dict = None) -> tuple[dict, dict]:
    """Builds per-zone drop rate tables and discovered species index from raw zone fishing data."""
    zone_loot_tables = {}
    discovered_species = {}
    custom_fish_cache = custom_fish_cache or {}

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

    # Incorporate Camelot local overrides (e.g. Zephras Isle & CMaNGOS dungeons)
    for uimap, entries in CAMELOT_LOCAL_OVERRIDES.items():
        if uimap not in AUTHORITATIVE_ZONE_SKILL:
            continue
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

    # Fallback: synthesize tier loot table + discovered custom fish for any fishable zone without Wowhead telemetry yet
    for uimap, req_skill in sorted(AUTHORITATIVE_ZONE_SKILL.items()):
        if uimap in zone_loot_tables:
            # Also inject any newly discovered custom fish into existing zone tables if not already present
            extra_custom = custom_fish_cache.get(str(uimap)) or []
            existing_ids = {row[0] for row in zone_loot_tables[uimap]}
            for fe in extra_custom:
                iid = int(fe["itemID"])
                if iid not in existing_ids:
                    zone_loot_tables[uimap].append([iid, fe["share"], fe["kind"]])
                    str_iid = str(iid)
                    sp_entry = discovered_species.setdefault(str_iid, {
                        "name": fe.get("name", ""),
                        "kind": fe["kind"],
                        "quality": 1,
                        "icon": existing_species.get(str_iid, {}).get("icon", ""),
                        "zones": [],
                    })
                    sp_entry["zones"].append({
                        "uimap": uimap,
                        "name": ZONE_NAMES.get(uimap, "").lower(),
                        "count": int(fe["share"] * 10),
                        "outof": 1000,
                        "share": fe["share"],
                    })
            continue

        # No crowdsourced table or override: synthesize from DEFAULT_TIER_FISHING_LOOT + custom fish
        tier_template = DEFAULT_TIER_FISHING_LOOT.get(req_skill) or DEFAULT_TIER_FISHING_LOOT.get(225, [])
        synth_entries = [dict(e) for e in tier_template]
        extra_custom = custom_fish_cache.get(str(uimap)) or []
        for fe in extra_custom:
            if not any(int(e["itemID"]) == int(fe["itemID"]) for e in synth_entries):
                if synth_entries:
                    synth_entries[0]["share"] = round(max(1.0, synth_entries[0]["share"] - float(fe["share"])), 1)
                synth_entries.append(dict(fe))

        if synth_entries:
            zone_loot_tables[uimap] = [[int(e["itemID"]), float(e["share"]), e["kind"]] for e in synth_entries]
            for e in synth_entries:
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
                    "count": int(float(e["share"]) * 10),
                    "outof": 1000,
                    "share": float(e["share"]),
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
        k for k, req in AUTHORITATIVE_ZONE_SKILL.items()
        if k < 100000 and req <= 150
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

    # ── 3b. Species Fallback Names & Water Habitats ──────────────────────────
    lines.append("-- Authoritative lowercase species names (fallback before client item cache resolves)")
    lines.append("D.SPECIES_NAMES = {")
    for str_iid in sorted(species_cache.keys(), key=lambda x: int(x)):
        sp = species_cache[str_iid]
        nm = (sp.get("name") or "").replace('"', '\\"')
        if nm:
            lines.append(f'    [{int(str_iid)}] = "{nm}",')
    lines.append("}")
    lines.append("")

    lines.append("-- Water habitat classification per species ('coastal' = ocean, 'inland' = lake/river, 'oasis' = Barrens oasis)")
    lines.append("D.SPECIES_HABITAT = {")
    for iid in sorted(SPECIES_HABITAT.keys()):
        lines.append(f'    [{iid}] = "{SPECIES_HABITAT[iid]}",')
    lines.append("}")
    lines.append("")

    lines.append("-- Zones containing both coastal (ocean) and inland (lake/river/oasis) waters")
    lines.append("D.MIXED_ZONES = {")
    for mid in sorted(MIXED_ZONES):
        zname = ZONE_NAMES.get(mid, f"Map {mid}")
        lines.append(f"    [{mid}] = true, -- {zname}")
    lines.append("}")
    lines.append("")

    lines.append("-- Authoritative lowercase zone names (fallback when C_Map.GetMapInfo is unavailable)")
    lines.append("D.ZONE_NAMES = {")
    for uimap in sorted(ZONE_NAMES.keys()):
        zname_low = ZONE_NAMES[uimap].lower().replace('"', '\\"')
        lines.append(f'    [{uimap}] = "{zname_low}",')
    lines.append("}")
    lines.append("")

    lines.append("-- Reverse lookup from lowercase zone/dungeon name to numeric mapID (for instance & custom zone resolution)")
    lines.append("D.ZONE_NAME_TO_ID = {")
    name_to_id_merged = {v.lower(): k for k, v in ZONE_NAMES.items()}
    name_to_id_merged.update(ALL_INSTANCE_NAME_TO_ID)
    for zname_low in sorted(name_to_id_merged.keys()):
        esc_name = zname_low.replace('"', '\\"')
        lines.append(f'    ["{esc_name}"] = {name_to_id_merged[zname_low]},')
    lines.append("}")
    lines.append("")

    lines.append("-- Authoritative continent classification per zone ('eastern_kingdoms' vs 'kalimdor')")
    lines.append("D.ZONE_CONTINENT = {")
    for uimap in sorted(ZONE_CONTINENT.keys()):
        lines.append(f'    [{uimap}] = "{ZONE_CONTINENT[uimap]}",')
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
    lines.append("                        habitat = D.SPECIES_HABITAT[itemID],")
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
    lines.append("    -- Merge any newly caught in-game species from SfuiDB.fishing.species not yet in static tables")
    lines.append("    local savedSpecies = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.species")
    lines.append("    if type(savedSpecies) == \"table\" then")
    lines.append("        for itemID, sData in pairs(savedSpecies) do")
    lines.append("            local id = tonumber(itemID)")
    lines.append("            if id and not speciesCatalog[id] and type(sData) == \"table\" and (sData.n or 0) > 0 then")
    lines.append("                local zID = sData.lz or sData.fz")
    lines.append("                local zReq = (zID and D.ZONE_SKILL[zID]) or 0")
    lines.append("                speciesCatalog[id] = {")
    lines.append("                    itemID = id,")
    lines.append('                    kind = "f",')
    lines.append("                    isContainer = false,")
    lines.append("                    habitat = D.SPECIES_HABITAT[id],")
    lines.append("                    minSkill = zReq,")
    lines.append("                    zones = zID and { { mapID = zID, share = 0, reqSkill = zReq, isClassicOnly = false } } or {},")
    lines.append("                }")
    lines.append("            end")
    lines.append("        end")
    lines.append("    end")
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
    lines.append("function D.InvalidateSpeciesCatalog()")
    lines.append("    speciesCatalog = nil")
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
    lines.append("--- Resolves lowercase display text (colored link or plain name) and icon texture for a species")
    lines.append("--- @param itemID number")
    lines.append("--- @param preferLink boolean|nil")
    lines.append("--- @return string displayText, string|number|nil texture, string|nil itemName, string|nil itemLink, number|nil quality")
    lines.append("function D.GetSpeciesDisplay(itemID, preferLink)")
    lines.append("    local common = sfui.common")
    lines.append("    local name, link, quality, _, _, _, _, _, _, texture")
    lines.append("    if common and common.get_item_info then")
    lines.append("        name, link, quality, _, _, _, _, _, _, texture = common.get_item_info(itemID)")
    lines.append("    end")
    lines.append('    local lowerLink = (preferLink ~= false and link) and link:gsub("%b[]", string.lower) or nil')
    lines.append('    local lowerName = (name and name:lower()) or (itemID and D.SPECIES_NAMES[itemID]) or ("item:" .. tostring(itemID or 0))')
    lines.append("    return (lowerLink or lowerName), texture, lowerName, lowerLink, quality")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns the lowercase name for a zone mapID")
    lines.append("--- @param mapID number")
    lines.append("--- @return string|nil")
    lines.append("function D.GetZoneName(mapID)")
    lines.append("    if not mapID then return nil end")
    lines.append("    if D.ZONE_NAMES[mapID] then return D.ZONE_NAMES[mapID] end")
    lines.append("    local savedZ = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.zones and _G.SfuiDB.fishing.zones[mapID]")
    lines.append('    if type(savedZ) == "table" and type(savedZ.name) == "string" and savedZ.name ~= "" then return savedZ.name:lower() end')
    lines.append("    local name = sfui.common and sfui.common.get_map_name and sfui.common.get_map_name(mapID)")
    lines.append("    return name and name:lower() or nil")
    lines.append("end")
    lines.append("")
    lines.append("--- Resolves a zone or dungeon name (e.g. from GetRealZoneText inside an instance) to a numeric mapID")
    lines.append("--- @param zoneText string|nil")
    lines.append("--- @return number")
    lines.append("function D.ResolveZoneNameID(zoneText)")
    lines.append('    if type(zoneText) ~= "string" or zoneText == "" then return 0 end')
    lines.append("    local low = zoneText:lower()")
    lines.append("    if D.ZONE_NAME_TO_ID[low] then return D.ZONE_NAME_TO_ID[low] end")
    lines.append('    local stripped = low:gsub("^the%s+", "")')
    lines.append("    if D.ZONE_NAME_TO_ID[stripped] then return D.ZONE_NAME_TO_ID[stripped] end")
    lines.append("    local h = 0")
    lines.append("    for i = 1, #low do")
    lines.append("        h = (h * 31 + low:byte(i)) % 89999")
    lines.append("    end")
    lines.append("    local dynID = 200000 + h")
    lines.append("    D.ZONE_NAMES[dynID] = low")
    lines.append("    D.ZONE_NAME_TO_ID[low] = dynID")
    lines.append("    return dynID")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns the continent key ('eastern_kingdoms' | 'kalimdor') and display label for a zone mapID")
    lines.append("--- @param mapID number")
    lines.append("--- @return string continentKey, string continentLabel")
    lines.append("function D.GetZoneContinent(mapID)")
    lines.append("    local key = mapID and D.ZONE_CONTINENT[mapID]")
    lines.append("    if not key and mapID and sfui.common and sfui.common.get_map_info then")
    lines.append("        local info = sfui.common.get_map_info(mapID)")
    lines.append("        local parentID = info and info.parentMapID")
    lines.append('        if parentID == 1414 then key = "kalimdor"')
    lines.append('        elseif parentID == 1415 then key = "eastern_kingdoms"')
    lines.append("        end")
    lines.append("    end")
    lines.append('    key = key or "eastern_kingdoms"')
    lines.append('    return key, (key == "kalimdor") and "kalimdor" or "eastern kingdoms"')
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
    lines.append("--- @return number requiredSkill, table|nil subAreaHint")
    lines.append("function D.GetZoneRequirement(mapID)")
    lines.append("    if not mapID or mapID <= 0 then return nil end")
    lines.append("    local req = D.ZONE_SKILL[mapID]")
    lines.append("    local sub = D.ZONE_SKILL_PARTS[mapID]")
    lines.append("    return req, sub")
    lines.append("end")
    lines.append("")
    lines.append("--- Returns water habitat ('coastal' | 'inland' | 'oasis' | nil) and formatted badge for a species")
    lines.append("--- @param itemID number")
    lines.append("--- @param mapID number|nil")
    lines.append("--- @return string|nil habitat, string|nil badge")
    lines.append("function D.GetSpeciesHabitat(itemID, mapID)")
    lines.append("    local hab = itemID and D.SPECIES_HABITAT[itemID]")
    lines.append("    if not hab then return nil, nil end")
    lines.append("    if mapID and not D.MIXED_ZONES[mapID] and hab ~= \"oasis\" then")
    lines.append("        return hab, nil")
    lines.append("    end")
    lines.append('    if hab == "coastal" then')
    lines.append('        return hab, "|cff44bbff[coast]|r"')
    lines.append('    elseif hab == "oasis" then')
    lines.append('        return hab, "|cffffcc44[oasis]|r"')
    lines.append('    elseif hab == "inland" then')
    lines.append('        return hab, "|cff66dd88[inland]|r"')
    lines.append("    end")
    lines.append("    return hab, nil")
    lines.append("end")
    lines.append("")
    lines.append("local COASTAL_KEYWORDS = {")
    lines.append('    "coast", "strand", "shore", "beach", "bay", "cove", "harbor", "port", "dock",')
    lines.append('    "anchorage", "isle", "island", "reef", "ratchet", "northwatch", "southshore",')
    lines.append('    "menethil", "auberdine", "zoram", "booty bay", "theramore", "feathermoon",')
    lines.append('    "sar\'theris", "shadowprey", "revantusk", "faldir", "rut\'theran", "longshore",')
    lines.append('    "lighthouse", "sen\'jin", "tiragarde", "sardor", "alcaz", "steamwheedle",')
    lines.append('    "powderfuse", "valanaar",')
    lines.append("}")
    lines.append("")
    lines.append("local INLAND_KEYWORDS = {")
    lines.append('    "lake", "river", "loch", "pond", "falls", "stream", "creek", "marsh",')
    lines.append('    "mystral", "falfarren", "iris", "nazferiti", "verdantis", "mennar",')
    lines.append('    "lordamere", "darrowmere", "tarren mill", "valorwind", "kurzen", "southfury",')
    lines.append('    "meadowsbrook", "turner", "shen\'dar", "nordrassil",')
    lines.append("}")
    lines.append("")
    lines.append("--- Resolves live sub-zone skill requirement and active water habitat ('coastal' | 'inland' | 'oasis')")
    lines.append("--- @param mapID number")
    lines.append("--- @param subZoneText string|nil")
    lines.append("--- @return number|nil reqSkill, table|nil subAreaHint, string|nil activeHabitat, string|nil matchedSubArea, boolean isMixed")
    lines.append("function D.ResolveSubZone(mapID, subZoneText)")
    lines.append("    if not mapID or mapID <= 0 then return nil, nil, nil, nil, false end")
    lines.append("    local req = D.ZONE_SKILL[mapID]")
    lines.append("    local sub = D.ZONE_SKILL_PARTS[mapID]")
    lines.append("    local isMixed = D.MIXED_ZONES[mapID] == true")
    lines.append('    local sz = (type(subZoneText) == "string" and subZoneText ~= "") and subZoneText:lower() or nil')
    lines.append("    if not sz then")
    lines.append("        return req, sub, nil, nil, isMixed")
    lines.append("    end")
    lines.append("")
    lines.append("    -- 1. Check high-skill sub-area overrides")
    lines.append('    if mapID == 1434 and sz:find("jaguero", 1, true) then')
    lines.append('        return 300, sub, "coastal", "jaguero isle", isMixed')
    lines.append('    elseif mapID == 1444 and sz:find("jademir", 1, true) then')
    lines.append('        return 425, sub, "inland", "jademir lake", isMixed')
    lines.append('    elseif mapID == 1447 and (sz:find("bay of storms", 1, true) or sz:find("scalebeard", 1, true) or sz:find("hetaera", 1, true) or sz:find("jagged reef", 1, true)) then')
    lines.append('        return 425, sub, "coastal", sz, isMixed')
    lines.append("    end")
    lines.append("")
    lines.append("    -- 2. Check Barrens Oases")
    lines.append('    if mapID == 1413 and (sz:find("oasis", 1, true) or sz:find("forgotten pools", 1, true) or sz:find("lushwater", 1, true) or sz:find("stagnant", 1, true) or sz:find("wailing caverns", 1, true)) then')
    lines.append('        return req, sub, "oasis", sz, isMixed')
    lines.append("    end")
    lines.append("")
    lines.append("    -- 3. Check Coastal vs Inland water keywords in mixed zones")
    lines.append("    if isMixed then")
    lines.append("        for _, kw in ipairs(COASTAL_KEYWORDS) do")
    lines.append("            if sz:find(kw, 1, true) then")
    lines.append('                return req, sub, "coastal", sz, isMixed')
    lines.append("            end")
    lines.append("        end")
    lines.append("        for _, kw in ipairs(INLAND_KEYWORDS) do")
    lines.append("            if sz:find(kw, 1, true) then")
    lines.append('                return req, sub, "inland", sz, isMixed')
    lines.append("            end")
    lines.append("        end")
    lines.append("    end")
    lines.append("")
    lines.append("    return req, sub, nil, nil, isMixed")
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
    lines.append("--- Returns all known fishing zones with their requirement and continent")
    lines.append("--- @return table array of { mapID, reqSkill, continent, sub }")
    lines.append("function D.GetAllWaters()")
    lines.append("    local waters = {}")
    lines.append("    local seen = {}")
    lines.append("    for mapID, req in pairs(D.ZONE_SKILL) do")
    lines.append("        seen[mapID] = true")
    lines.append("        local contKey = D.GetZoneContinent(mapID)")
    lines.append("        waters[#waters + 1] = {")
    lines.append("            mapID = mapID,")
    lines.append("            reqSkill = req,")
    lines.append("            continent = contKey,")
    lines.append("            sub = D.ZONE_SKILL_PARTS[mapID],")
    lines.append("        }")
    lines.append("    end")
    lines.append("    local savedZones = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.zones")
    lines.append("    if type(savedZones) == \"table\" then")
    lines.append("        for mKey, zData in pairs(savedZones) do")
    lines.append("            local mID = tonumber(mKey)")
    lines.append("            if mID and mID > 0 and not seen[mID] and type(zData) == \"table\" and (zData.catches or 0) > 0 then")
    lines.append("                seen[mID] = true")
    lines.append("                waters[#waters + 1] = {")
    lines.append("                    mapID = mID,")
    lines.append("                    reqSkill = 225,")
    lines.append("                    continent = D.GetZoneContinent(mID),")
    lines.append("                }")
    lines.append("            end")
    lines.append("        end")
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
    lines.append("if sfui.events and sfui.events.RegisterMessage then")
    lines.append('    sfui.events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", function(_, itemID)')
    lines.append("        if itemID and speciesCatalog and not speciesCatalog[itemID] then")
    lines.append("            speciesCatalog = nil")
    lines.append("        end")
    lines.append("    end)")
    lines.append("end")
    lines.append("")

    content = "\n".join(lines) + "\n"
    changed = write_lua_atomically(LUA_TARGET, content, dry_run=dry_run)
    if not dry_run:
        status_msg = "Updated" if changed else "Up-to-date"
        print(f"[{status_msg}] Authoritative Lua database: {LUA_TARGET} ({len(lines)} lines)")


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
