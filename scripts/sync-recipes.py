#!/usr/bin/env python3
"""
SFUI Recipe & Source Synchronizer (Camelot / Classic Forever)
Automates pulling recipe spells, items, reagents, skill brackets, and source locations
(trainers, vendors, drops, quests) from Wowhead Forever endpoints:
  - https://www.wowhead.com/forever/spells/professions/
  - https://www.wowhead.com/forever/spells/secondary-skills/
  - https://www.wowhead.com/forever/items/recipes/
  - https://www.wowhead.com/forever/npc=

Outputs:
  - data/recipes_wowhead.json (raw intermediate scrape cache)
  - data/recipes_npcs.json (NPC mapID and coordinate cache)
  - data/recipes_camelot.lua (authoritative Lua database for SFUI on Camelot)

Usage:
    python3 scripts/sync-recipes.py [--refresh] [--professions cooking,alchemy] [--dry-run] [--check] [--verbose]
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
from concurrent.futures import ThreadPoolExecutor

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DATA_DIR = os.path.join(REPO_ROOT, "data")
CACHE_FILE = os.path.join(DATA_DIR, "recipes_wowhead.json")
NPC_CACHE_FILE = os.path.join(DATA_DIR, "recipes_npcs.json")
ZONE_CACHE_FILE = os.path.join(DATA_DIR, "recipes_zones.json")
REP_CACHE_FILE = os.path.join(DATA_DIR, "recipes_rep_cache.json")
LUA_TARGET = os.path.join(DATA_DIR, "recipes_camelot.lua")

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
}

PROFESSIONS = {
    "cooking":        { "skillID": 185, "type": "secondary", "name": "Cooking" },
    "first-aid":      { "skillID": 129, "type": "secondary", "name": "First Aid" },
    "alchemy":        { "skillID": 171, "type": "primary",   "name": "Alchemy" },
    "blacksmithing":  { "skillID": 164, "type": "primary",   "name": "Blacksmithing" },
    "enchanting":     { "skillID": 333, "type": "primary",   "name": "Enchanting" },
    "engineering":    { "skillID": 202, "type": "primary",   "name": "Engineering" },
    "leatherworking": { "skillID": 165, "type": "primary",   "name": "Leatherworking" },
    "tailoring":      { "skillID": 197, "type": "primary",   "name": "Tailoring" },
}

SOURCE_TYPES = {
    1: "craft",
    2: "drop",
    3: "pvp",
    4: "quest",
    5: "vendor",
    6: "trainer",
    16: "event",
    21: "discovery",
}

MANUAL_ALIASES = {
    "mithrilheadtrout": "mithrilheadedtrout",
    "elixirofdetectlesserinvisibility": "draughtofdetectlesserinvisibility",
    "greaterdreamlesssleep": "greaterdreamlesssleeppotion",
    "clusterlauncher": "fireworkclusterlauncher",
    "gnomishalarmobot": "alarmobot",
    "enchantbracerhealing": "enchantbracerhealingpower",
}

EVENT_MAP = {
    # Feast of Winter Veil
    21143: "winter_veil",     # Gingerbread Cookie
    21144: "winter_veil",     # Egg Nog
    21913: "winter_veil",     # Edge of Winter
    21931: "winter_veil",     # Enchant Weapon - Winter's Might
    21940: "winter_veil",     # Snowmaster 9000
    21943: "winter_veil",     # Gloves of the Greatfather
    21945: "winter_veil",     # Green Holiday Shirt
    44950: "winter_veil",     # Green Winter Clothes
    44953: "winter_veil",     # Winter Boots
    44958: "winter_veil",     # Red Winter Clothes

    # Lunar Festival
    23066: "lunar_festival",  # Red Firework
    23067: "lunar_festival",  # Blue Firework
    23068: "lunar_festival",  # Green Firework
    23507: "lunar_festival",  # Snake Burst Firework
    26403: "lunar_festival",  # Festival Dress
    26407: "lunar_festival",  # Festival Suit
    26416: "lunar_festival",  # Small Blue Rocket
    26417: "lunar_festival",  # Small Green Rocket
    26418: "lunar_festival",  # Small Red Rocket
    26420: "lunar_festival",  # Large Blue Rocket
    26421: "lunar_festival",  # Large Green Rocket
    26422: "lunar_festival",  # Large Red Rocket
    26423: "lunar_festival",  # Blue Rocket Cluster
    26424: "lunar_festival",  # Green Rocket Cluster
    26425: "lunar_festival",  # Red Rocket Cluster
    26426: "lunar_festival",  # Large Blue Rocket Cluster
    26427: "lunar_festival",  # Large Green Rocket Cluster
    26428: "lunar_festival",  # Large Red Rocket Cluster
    26442: "lunar_festival",  # Firework Launcher
    26443: "lunar_festival",  # Firework Cluster Launcher

    # Midsummer Fire Festival
    29699: "midsummer",       # Toasted Smorcs
    29700: "midsummer",       # Midsummer Sausage
    29701: "midsummer",       # Fire-Toasted Bun
    29702: "midsummer",       # Elderberry Pie
    23083: "midsummer",       # Captured Flame
    23412: "midsummer",       # Brazier of Dancing Flames

    # Darkmoon Faire
    23403: "darkmoon_faire",  # Frog Illusions
    24718: "darkmoon_faire",  # Darkmoon Storage Box
    24719: "darkmoon_faire",  # Greater Darkmoon Storage Box

    # Stranglethorn Fishing Extravaganza
    25958: "fishing_extravaganza", # Arcanite Fishing Pole
    25959: "fishing_extravaganza", # Hook of the Master Angler
    25960: "fishing_extravaganza", # Nat Pagle's Extreme Angler FC-5000
    25961: "fishing_extravaganza", # High-test Fishing Line / Boots

    # Harvest Festival
    21746: "harvest_festival", # Harvest Bread
    21747: "harvest_festival", # Harvest Nectar
    21748: "harvest_festival", # Harvest Boar
}

SPECIALIZATION_RECIPES = {
    # Engineering: Goblin Engineering
    3968: "goblin engineering",   # Goblin Land Mine
    8895: "goblin engineering",   # Goblin Rocket Boots
    9273: "goblin engineering",   # Goblin Jumper Cables
    12715: "goblin engineering",  # Goblin Rocket Fuel Recipe
    12716: "goblin engineering",  # Goblin Mortar
    12717: "goblin engineering",  # Goblin Mining Helmet
    12718: "goblin engineering",  # Goblin Construction Helmet
    12755: "goblin engineering",  # Goblin Bomb Dispenser
    12758: "goblin engineering",  # Goblin Rocket Helmet
    12760: "goblin engineering",  # Goblin Sapper Charge
    12908: "goblin engineering",  # Goblin Dragon Gun
    23078: "goblin engineering",  # Goblin Jumper Cables XL
    23486: "goblin engineering",  # Dimensional Ripper - Everlook
    1266936: "goblin engineering",
    1266938: "goblin engineering",

    # Engineering: Gnomish Engineering
    3971: "gnomish engineering",   # Gnomish Cloaking Device
    9269: "gnomish engineering",   # Gnomish Universal Remote
    12714: "gnomish engineering",  # Gnomish Goggles
    12759: "gnomish engineering",  # Gnomish Death Ray
    12897: "gnomish engineering",  # Gnomish Goggles
    12899: "gnomish engineering",  # Gnomish Shrink Ray
    12902: "gnomish engineering",  # Gnomish Net-o-Matic Projector
    12903: "gnomish engineering",  # Gnomish Harm Prevention Belt
    12905: "gnomish engineering",  # Gnomish Rocket Boots
    12906: "gnomish engineering",  # Gnomish Battle Chicken
    12907: "gnomish engineering",  # Gnomish Mind Control Cap
    23082: "gnomish engineering",  # World Enlarger
    23489: "gnomish engineering",  # Ultrasafe Transporter - Gadgetzan
    1266924: "gnomish engineering",
    1266935: "gnomish engineering",
    1266937: "gnomish engineering",
    1266939: "gnomish engineering",

    # Blacksmithing: Armorsmith
    16648: "armorsmith",  # Radiant Breastplate
    16654: "armorsmith",  # Radiant Gloves
    16656: "armorsmith",  # Radiant Boots
    16659: "armorsmith",  # Radiant Circlet
    16660: "armorsmith",  # Dawnbringer Shoulders
    16661: "armorsmith",  # Storm Gauntlets
    16728: "armorsmith",  # Helm of the Great Chief
    20853: "armorsmith",  # Fiery Chain Girdle
    20854: "armorsmith",  # Dark Iron Bracers
    20855: "armorsmith",  # Dark Iron Helm
    20857: "armorsmith",  # Fiery Chain Shoulders
    20872: "armorsmith",  # Fiery Chain Girdle
    20873: "armorsmith",  # Fiery Chain Shoulders
    20874: "armorsmith",  # Dark Iron Bracers
    20876: "armorsmith",  # Dark Iron Leggings
    20890: "armorsmith",  # Dark Iron Reaver
    23628: "armorsmith",  # Dark Iron Gauntlets
    23636: "armorsmith",  # Dark Iron Helm
    23637: "armorsmith",  # Dark Iron Gauntlets
    24136: "armorsmith",  # Bloodsoul Breastplate
    24137: "armorsmith",  # Bloodsoul Shoulders
    24138: "armorsmith",  # Bloodsoul Gauntlets
    24395: "armorsmith",  # Bloodsoul Gauntlets
    24396: "armorsmith",  # Bloodsoul Shoulders
    24397: "armorsmith",  # Bloodsoul Breastplate
    24399: "armorsmith",  # Dark Iron Boots
    28242: "armorsmith",  # Ironvine Bracers
    28243: "armorsmith",  # Ironvine Belt
    28244: "armorsmith",  # Ironvine Breastplate
    28461: "armorsmith",  # Ironvine Breastplate
    28462: "armorsmith",  # Ironvine Gloves
    28463: "armorsmith",  # Ironvine Belt

    # Blacksmithing: Weaponsmith
    10015: "weaponsmith", # Truesilver Champion
    15292: "weaponsmith", # Dark Iron Pulverizer
    16970: "weaponsmith", # Dawn's Edge
    16978: "weaponsmith", # Blazing Rapier
    16983: "weaponsmith", # Serenity
    16984: "weaponsmith", # Volcanic Hammer
    20897: "weaponsmith", # Dark Iron Destroyer
    20950: "weaponsmith", # Sulfuron Hammer
    21161: "weaponsmith", # Sulfuron Hammer
    23624: "weaponsmith", # Dawn's Edge
    23629: "weaponsmith", # Nightfall
    23653: "weaponsmith", # Nightfall

    # Leatherworking: Dragonscale Leatherworking
    10619: "dragonscale leatherworking",  # Dragonscale Gauntlets
    10650: "dragonscale leatherworking",  # Dragonscale Breastplate
    19050: "dragonscale leatherworking",  # Green Dragonscale Breastplate
    19054: "dragonscale leatherworking",  # Red Dragonscale Breastplate
    19060: "dragonscale leatherworking",  # Green Dragonscale Leggings
    19077: "dragonscale leatherworking",  # Blue Dragonscale Breastplate
    19085: "dragonscale leatherworking",  # Black Dragonscale Breastplate
    19089: "dragonscale leatherworking",  # Blue Dragonscale Shoulders
    19094: "dragonscale leatherworking",  # Black Dragonscale Shoulders
    19107: "dragonscale leatherworking",  # Black Dragonscale Leggings
    20855: "dragonscale leatherworking",  # Black Dragonscale Boots
    24654: "dragonscale leatherworking",  # Blue Dragonscale Leggings
    24655: "dragonscale leatherworking",  # Green Dragonscale Gauntlets
    24849: "dragonscale leatherworking",  # Sandstalker Bracers
    24850: "dragonscale leatherworking",  # Sandstalker Gauntlets
    24851: "dragonscale leatherworking",  # Sandstalker Breastplate

    # Leatherworking: Elemental Leatherworking
    19061: "elemental leatherworking",  # Living Shoulders
    19067: "elemental leatherworking",  # Stormshroud Pants
    19078: "elemental leatherworking",  # Living Leggings
    19079: "elemental leatherworking",  # Stormshroud Armor
    19090: "elemental leatherworking",  # Stormshroud Shoulders
    19095: "elemental leatherworking",  # Living Breastplate
    20761: "elemental leatherworking",  # Molten Helm
    20768: "elemental leatherworking",  # Corehound Boots
    20853: "elemental leatherworking",  # Corehound Boots
    20854: "elemental leatherworking",  # Molten Helm
    23630: "elemental leatherworking",  # Lava Belt
    23707: "elemental leatherworking",  # Lava Belt
    24846: "elemental leatherworking",  # Spitfire Bracers
    24847: "elemental leatherworking",  # Spitfire Gauntlets
    24848: "elemental leatherworking",  # Spitfire Breastplate
    26279: "elemental leatherworking",  # Stormshroud Gloves

    # Leatherworking: Tribal Leatherworking
    10621: "tribal leatherworking",  # Wolfshead Helm
    10647: "tribal leatherworking",  # Feathered Breastplate
    19062: "tribal leatherworking",  # Ironfeather Shoulders
    19066: "tribal leatherworking",  # Frostsaber Boots
    19068: "tribal leatherworking",  # Warbear Harness
    19074: "tribal leatherworking",  # Frostsaber Leggings
    19080: "tribal leatherworking",  # Warbear Woolies
    19084: "tribal leatherworking",  # Devilsaur Gauntlets
    19086: "tribal leatherworking",  # Ironfeather Breastplate
    19087: "tribal leatherworking",  # Frostsaber Gloves
    19097: "tribal leatherworking",  # Devilsaur Leggings
    19104: "tribal leatherworking",  # Frostsaber Tunic
    23703: "tribal leatherworking",  # Might of the Timbermaw
    23704: "tribal leatherworking",  # Timbermaw Brawlers
    24121: "tribal leatherworking",  # Primal Batskin Jerkin
    24122: "tribal leatherworking",  # Primal Batskin Gloves
    24123: "tribal leatherworking",  # Primal Batskin Bracers
    28472: "tribal leatherworking",  # Bramblewood Helm
    28473: "tribal leatherworking",  # Bramblewood Boots
    28474: "tribal leatherworking",  # Bramblewood Belt
}

REPUTATION_RECIPES = {
    # Thorium Brotherhood (Lokhtos Darkbargainer, BRD Grim Guzzler, npc 12944)
    # Friendly
    11479: { "faction": "thorium brotherhood", "standing": "friendly" }, # transmute: iron to gold
    9303:  { "faction": "thorium brotherhood", "standing": "friendly" },
    # Honored
    20872: { "faction": "thorium brotherhood", "standing": "honored", "tokens": "dark iron ore x10" }, # fiery chain girdle
    17049: { "faction": "thorium brotherhood", "standing": "honored", "tokens": "dark iron ore x10" },
    20874: { "faction": "thorium brotherhood", "standing": "honored", "tokens": "dark iron ore x15" }, # dark iron bracers
    17051: { "faction": "thorium brotherhood", "standing": "honored", "tokens": "dark iron ore x15" },
    13898: { "faction": "thorium brotherhood", "standing": "honored" }, # enchant weapon - fiery weapon
    20008: { "faction": "thorium brotherhood", "standing": "honored" },
    16214: { "faction": "thorium brotherhood", "standing": "honored" },
    20854: { "faction": "thorium brotherhood", "standing": "honored" }, # molten helm
    20761: { "faction": "thorium brotherhood", "standing": "honored" },
    17022: { "faction": "thorium brotherhood", "standing": "honored" },
    20849: { "faction": "thorium brotherhood", "standing": "honored" }, # flarecore gloves
    20766: { "faction": "thorium brotherhood", "standing": "honored" },
    17023: { "faction": "thorium brotherhood", "standing": "honored" },
    20853: { "faction": "thorium brotherhood", "standing": "honored" }, # corehound boots
    20768: { "faction": "thorium brotherhood", "standing": "honored" },
    17025: { "faction": "thorium brotherhood", "standing": "honored" },
    # Revered
    23636: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x20" }, # dark iron helm
    20855: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x20" },
    17052: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x20" },
    20897: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x25" }, # dark iron destroyer
    20856: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x25" },
    17053: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x25" },
    20873: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x20" }, # fiery chain shoulders
    20857: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x20" },
    17050: { "faction": "thorium brotherhood", "standing": "revered", "tokens": "dark iron ore x20" },
    23666: { "faction": "thorium brotherhood", "standing": "revered" }, # flarecore robe
    20770: { "faction": "thorium brotherhood", "standing": "revered" },
    17024: { "faction": "thorium brotherhood", "standing": "revered" },
    20848: { "faction": "thorium brotherhood", "standing": "revered" }, # flarecore mantle
    24136: { "faction": "thorium brotherhood", "standing": "revered" },
    19448: { "faction": "thorium brotherhood", "standing": "revered" },
    23707: { "faction": "thorium brotherhood", "standing": "revered" }, # lava belt
    23630: { "faction": "thorium brotherhood", "standing": "revered" },
    19219: { "faction": "thorium brotherhood", "standing": "revered" },
    # Exalted
    20876: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "dark iron ore x30" }, # dark iron leggings
    20874: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "dark iron ore x30" },
    17059: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "dark iron ore x30" },
    20890: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "dark iron ore x30" }, # dark iron reaver
    17060: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "dark iron ore x30" },
    21161: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "sulfuron ingot" },    # sulfuron hammer
    20950: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "sulfuron ingot" },
    17161: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "sulfuron ingot" },
    23637: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "blood of the mountain x2" }, # dark iron gauntlets
    23628: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "blood of the mountain x2" },
    19207: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "blood of the mountain x2" },
    23653: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "fiery core x2" },    # nightfall
    23629: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "fiery core x2" },
    19206: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "fiery core x2" },
    24138: { "faction": "thorium brotherhood", "standing": "exalted" }, # bloodsoul gauntlets
    24395: { "faction": "thorium brotherhood", "standing": "exalted" },
    19776: { "faction": "thorium brotherhood", "standing": "exalted" },
    24137: { "faction": "thorium brotherhood", "standing": "exalted" }, # bloodsoul shoulders
    24396: { "faction": "thorium brotherhood", "standing": "exalted" },
    19777: { "faction": "thorium brotherhood", "standing": "exalted" },
    24136: { "faction": "thorium brotherhood", "standing": "exalted" }, # bloodsoul breastplate
    24397: { "faction": "thorium brotherhood", "standing": "exalted" },
    19778: { "faction": "thorium brotherhood", "standing": "exalted" },
    24399: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "lava core x2" },     # dark iron boots
    20040: { "faction": "thorium brotherhood", "standing": "exalted", "tokens": "lava core x2" },
    23667: { "faction": "thorium brotherhood", "standing": "exalted" }, # flarecore leggings
    24137: { "faction": "thorium brotherhood", "standing": "exalted" },
    19449: { "faction": "thorium brotherhood", "standing": "exalted" },

    # Timbermaw Hold (Meilosh, Felwood, npc 11557)
    # Friendly
    19068: { "faction": "timbermaw hold", "standing": "friendly" }, # warbear harness
    19097: { "faction": "timbermaw hold", "standing": "friendly" },
    15760: { "faction": "timbermaw hold", "standing": "friendly" },
    19080: { "faction": "timbermaw hold", "standing": "friendly" }, # warbear woolies
    19098: { "faction": "timbermaw hold", "standing": "friendly" },
    15761: { "faction": "timbermaw hold", "standing": "friendly" },
    23802: { "faction": "timbermaw hold", "standing": "friendly" }, # enchant bracer - healing power
    23801: { "faction": "timbermaw hold", "standing": "friendly" },
    19442: { "faction": "timbermaw hold", "standing": "friendly" },
    17561: { "faction": "timbermaw hold", "standing": "friendly" }, # transmute earth to water
    17562: { "faction": "timbermaw hold", "standing": "friendly" },
    13484: { "faction": "timbermaw hold", "standing": "friendly" },
    # Honored
    23628: { "faction": "timbermaw hold", "standing": "honored" }, # heavy timbermaw belt
    24387: { "faction": "timbermaw hold", "standing": "honored" },
    19767: { "faction": "timbermaw hold", "standing": "honored" },
    23629: { "faction": "timbermaw hold", "standing": "honored" }, # heavy timbermaw boots
    23663: { "faction": "timbermaw hold", "standing": "honored" }, # mantle of the timbermaw
    24389: { "faction": "timbermaw hold", "standing": "honored" },
    19769: { "faction": "timbermaw hold", "standing": "honored" },
    23704: { "faction": "timbermaw hold", "standing": "honored" }, # timbermaw brawlers
    24390: { "faction": "timbermaw hold", "standing": "honored" },
    19770: { "faction": "timbermaw hold", "standing": "honored" },
    27837: { "faction": "timbermaw hold", "standing": "honored" }, # enchant 2h weapon - agility
    22392: { "faction": "timbermaw hold", "standing": "honored" },
    # Revered
    23662: { "faction": "timbermaw hold", "standing": "revered" }, # wisdom of the timbermaw
    23800: { "faction": "timbermaw hold", "standing": "revered" }, # enchant weapon - agility
    19445: { "faction": "timbermaw hold", "standing": "revered" },
    17559: { "faction": "timbermaw hold", "standing": "revered" }, # transmute air to fire
    17565: { "faction": "timbermaw hold", "standing": "revered" },
    13482: { "faction": "timbermaw hold", "standing": "revered" },
    # Exalted
    23703: { "faction": "timbermaw hold", "standing": "exalted" }, # might of the timbermaw
    24391: { "faction": "timbermaw hold", "standing": "exalted" },
    19771: { "faction": "timbermaw hold", "standing": "exalted" },

    # Zandalar Tribe (Rin'wosho the Vahiti, Yojamba Isle, npc 14921)
    # Friendly
    24356: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" }, # bloodvine goggles
    20000: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    24093: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" }, # bloodvine boots
    24357: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    19764: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    24123: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" }, # primal batskin bracers
    24360: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    19767: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    24365: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" }, # mageblood elixir
    19779: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    24366: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" }, # greater dreamless sleep potion
    20011: { "faction": "zandalar tribe", "standing": "friendly", "tokens": "zandalar honor token" },
    # Honored
    24092: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },  # bloodvine leggings
    24358: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },
    19765: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },
    24122: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },  # primal batskin gloves
    24361: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },
    19768: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },
    24368: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },  # major troll's blood elixir
    20012: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },
    24367: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },  # living action potion
    20013: { "faction": "zandalar tribe", "standing": "honored", "tokens": "zandalar honor token" },
    # Revered
    24091: { "faction": "zandalar tribe", "standing": "revered", "tokens": "zandalar honor token" },  # bloodvine vest
    24359: { "faction": "zandalar tribe", "standing": "revered", "tokens": "zandalar honor token" },
    19766: { "faction": "zandalar tribe", "standing": "revered", "tokens": "zandalar honor token" },
    24121: { "faction": "zandalar tribe", "standing": "revered", "tokens": "zandalar honor token" },  # primal batskin jerkin
    24362: { "faction": "zandalar tribe", "standing": "revered", "tokens": "zandalar honor token" },
    19769: { "faction": "zandalar tribe", "standing": "revered", "tokens": "zandalar honor token" },

    # Argent Dawn (Quartermaster Miranda Breechlock, Light's Hope Chapel, npc 11039)
    # Friendly
    7934:  { "faction": "argent dawn", "standing": "friendly", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # powerful anti-venom
    # Honored
    23632: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # girdle of the dawn
    24388: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 },
    19768: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 },
    23633: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # gloves of the dawn
    23705: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # dawn treaders
    23706: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # golden mantle of the dawn
    23664: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # argent boots
    23665: { "faction": "argent dawn", "standing": "honored", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # argent shoulders
    # Revered
    23801: { "faction": "argent dawn", "standing": "revered", "npcID": 11039, "npcName": "quartermaster miranda breechlock", "zone": "eastern plaguelands", "mapID": 1423, "x": 0.816, "y": 0.578 }, # enchant bracer - mana regeneration
    # Exalted / Craftsman's Writs (Light's Hope Chapel)
    28242: { "faction": "argent dawn", "standing": "exalted" }, # icebane breastplate
    22756: { "faction": "argent dawn", "standing": "exalted" },
    28243: { "faction": "argent dawn", "standing": "exalted" }, # icebane gauntlets
    22757: { "faction": "argent dawn", "standing": "exalted" },
    28244: { "faction": "argent dawn", "standing": "exalted" }, # icebane bracers
    22758: { "faction": "argent dawn", "standing": "exalted" },
    28219: { "faction": "argent dawn", "standing": "exalted" }, # polar tunic
    28220: { "faction": "argent dawn", "standing": "exalted" }, # polar gloves
    28221: { "faction": "argent dawn", "standing": "exalted" }, # polar bracers
    28222: { "faction": "argent dawn", "standing": "exalted" }, # icy scale breastplate
    28223: { "faction": "argent dawn", "standing": "exalted" }, # icy scale gauntlets
    28224: { "faction": "argent dawn", "standing": "exalted" }, # icy scale bracers
    28205: { "faction": "argent dawn", "standing": "exalted" }, # glacial gloves
    28207: { "faction": "argent dawn", "standing": "exalted" }, # glacial vest
    28208: { "faction": "argent dawn", "standing": "exalted" }, # glacial cloak
    28209: { "faction": "argent dawn", "standing": "exalted" }, # glacial wrists

    # Cenarion Circle (Aelgeth 15176 / Vargus 15179 in Silithus Cenarion Hold)
    # Friendly
    24849: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # sandstalker bracers
    24900: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    20576: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    24847: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # spitfire gauntlets
    24901: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    20577: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    28462: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15179, "npcName": "vargus", "zone": "silithus", "mapID": 1451, "x": 0.498, "y": 0.364 }, # ironvine gloves
    28473: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # bramblewood boots
    28245: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    22759: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    28482: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # sylvan shoulders
    28248: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    22762: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    25078: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant gloves - fire power
    20726: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    25074: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant gloves - frost power
    25081: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant cloak - greater fire resistance
    25086: { "faction": "cenarion circle", "standing": "friendly", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant cloak - dodge
    # Honored
    24846: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # spitfire bracers
    24902: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    20578: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    24850: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # sandstalker gauntlets
    24903: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    20579: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    28463: { "faction": "cenarion circle", "standing": "honored", "npcID": 15179, "npcName": "vargus", "zone": "silithus", "mapID": 1451, "x": 0.498, "y": 0.364 }, # ironvine belt
    28474: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # bramblewood belt
    28246: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    22760: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    28481: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # sylvan crown
    28249: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    22763: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    25079: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant gloves - healing power
    25080: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant gloves - superior agility
    25083: { "faction": "cenarion circle", "standing": "honored", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant cloak - stealth
    # Revered
    24848: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # spitfire breastplate
    24904: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    20580: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    24851: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # sandstalker breastplate
    24905: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    20581: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    28461: { "faction": "cenarion circle", "standing": "revered", "npcID": 15179, "npcName": "vargus", "zone": "silithus", "mapID": 1451, "x": 0.498, "y": 0.364 }, # ironvine breastplate
    28472: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # bramblewood helm
    28247: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    22761: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    28480: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # sylvan vest
    28250: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    22764: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    25082: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant cloak - greater nature resistance
    20733: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
    25084: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 }, # enchant cloak - subtlety
    20735: { "faction": "cenarion circle", "standing": "revered", "npcID": 15176, "npcName": "aelgeth", "zone": "silithus", "mapID": 1451, "x": 0.512, "y": 0.388 },
}

UNIQUE_ENCOUNTER_SOURCES = {
    # Field Repair Bot 74A (on floor near Golem Lord Argelmach in BRD)
    22704: [
        {
            "type": "object",
            "name": "schematic on floor near golem lord argelmach",
            "zone": "blackrock depths",
            "mapID": 1584,
        }
    ],
    # Dirge's Kickin' Chimaerok Chops (quest reward from the scepter of the shifting sands chain)
    25659: [
        {
            "type": "quest",
            "name": "dirge's kickin' chimaerok chops (the scepter of the shifting sands)",
            "questID": 8313,
            "zone": "tanaris",
        }
    ],
    # Smoked Desert Dumplings (quest 'sharing the knowledge' from calandrath in silithus)
    24801: [
        {
            "type": "quest",
            "name": "sharing the knowledge (calandrath)",
            "questID": 8307,
            "zone": "silithus",
        }
    ],
}

WOWHEAD_ZONES = {
    1: "dun morogh",
    3: "badlands",
    4: "blasted lands",
    8: "swamp of sorrows",
    10: "duskwood",
    11: "wetlands",
    12: "loch modan",
    14: "durotar",
    15: "dustwallow marsh",
    16: "azshara",
    17: "the barrens",
    28: "western plaguelands",
    33: "stranglethorn vale",
    36: "alterac mountains",
    38: "loch modan",
    40: "westfall",
    41: "deadwind pass",
    44: "redridge mountains",
    45: "arathi highlands",
    46: "burning steppes",
    47: "the hinterlands",
    51: "searing gorge",
    85: "tirisfal glades",
    130: "silverpine forest",
    139: "eastern plaguelands",
    141: "teldrassil",
    148: "darkshore",
    209: "shadowfang keep",
    215: "mulgore",
    267: "hillsbrad foothills",
    331: "ashenvale",
    357: "feralas",
    361: "felwood",
    400: "thousand needles",
    405: "desolace",
    406: "stonetalon mountains",
    440: "tanaris",
    490: "un'goro crater",
    493: "moonglade",
    618: "winterspring",
    718: "wailing caverns",
    719: "blackfathom deeps",
    721: "gnomeregan",
    722: "razorfen kraul",
    796: "scarlet monastery",
    1176: "zul'farrak",
    1337: "uldaman",
    1377: "silithus",
    1417: "sunken temple",
    1477: "sunken temple",
    1519: "stormwind city",
    1537: "ironforge",
    1581: "the deadmines",
    1583: "blackrock spire",
    1584: "blackrock depths",
    1637: "orgrimmar",
    1657: "darnassus",
    1977: "zul'gurub",
    2017: "stratholme",
    2057: "scholomance",
    2557: "dire maul",
    2717: "molten core",
    3428: "temple of ahn'qiraj",
    3429: "ruins of ahn'qiraj",
    # Classic Forever / Camelot New Zones
    616: "mount hyjal",
    16236: "scarlet enclave",
    16591: "riverglades",
    16593: "zephras isle",
    16611: "ruins of lordaeron",
}



def clean_recipe_name(name: str) -> str:
    if not name:
        return ""
    # Strip common recipe prefixes
    s = re.sub(r"^(recipe|pattern|plans|schematic|formula|manual|book|blueprint):\s*", "", name.strip(), flags=re.IGNORECASE)
    return s.strip()

def norm_key(name: str) -> str:
    s = clean_recipe_name(name)
    return re.sub(r"[^a-zA-Z0-9]", "", s).lower()

def escape_lua_str(val: str) -> str:
    if not val:
        return ""
    return str(val).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def parse_relaxed_json(raw: str):
    """Parses relaxed JavaScript object literal syntax returned in Wowhead variables."""
    # Quote unquoted property names: e.g. { id: 123, name: "foo" }
    fixed = re.sub(r'([,{]\s*)([a-zA-Z0-9_]+)\s*:', r'\1"\2":', raw)
    # Remove trailing commas before } or ]
    fixed = re.sub(r',\s*([}\]])', r'\1', fixed)
    return json.loads(fixed)

def fetch_url(url: str, timeout: int = 12, max_retries: int = 3) -> str:
    req = urllib.request.Request(url, headers=HEADERS)
    last_err = None
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                # Handle gzip decompression
                enc = resp.info().get("Content-Encoding", "").lower()
                if "gzip" in enc or (len(raw) >= 2 and raw[:2] == b"\x1f\x8b"):
                    try:
                        raw = gzip.decompress(raw)
                    except Exception:
                        pass
                return raw.decode("utf-8", errors="ignore")
        except Exception as e:
            last_err = e
            if attempt < max_retries - 1:
                sleep_sec = 1.0 * (2 ** attempt)
                time.sleep(sleep_sec)
    print(f"Warning: Failed to fetch {url} after {max_retries} attempts: {last_err}", file=sys.stderr)
    return ""

def compact_spell(sp: dict) -> dict:
    keep_keys = ("id", "name", "rank", "learnedat", "colors", "creates", "trainingcost", "reagents", "source", "sourcemore")
    return {k: sp[k] for k in keep_keys if k in sp and sp[k] is not None}

def compact_item(it: dict) -> dict:
    keep_keys = ("id", "name", "source", "sourcemore", "buyprice")
    return {k: it[k] for k in keep_keys if k in it and it[k] is not None}

def fetch_spells_for_profession(prof_slug: str, prof_info: dict) -> list:
    sub = "secondary-skills" if prof_info["type"] == "secondary" else "professions"
    url = f"https://www.wowhead.com/forever/spells/{sub}/{prof_slug}"
    try:
        html = fetch_url(url)
        if not html:
            return []
        m = re.search(r"var listviewspells = (\[.*?\]);", html)
        if m:
            data = parse_relaxed_json(m.group(1))
            return [compact_spell(sp) for sp in data]
    except Exception as e:
        print(f"Warning: Failed to parse spells for {prof_slug}: {e}", file=sys.stderr)
    return []

def fetch_recipe_items_for_profession(prof_slug: str) -> list:
    url = f"https://www.wowhead.com/forever/items/recipes/{prof_slug}"
    try:
        html = fetch_url(url)
        if not html:
            return []
        m = re.search(r"var listviewitems = (\[.*?\]);", html)
        if m:
            data = parse_relaxed_json(m.group(1))
            return [compact_item(it) for it in data]
    except Exception as e:
        print(f"Warning: Failed to parse recipe items for {prof_slug}: {e}", file=sys.stderr)
    return []

def fetch_npc_location(npc_id: int) -> dict:
    url = f"https://www.wowhead.com/forever/npc={npc_id}"
    try:
        html = fetch_url(url, timeout=8, max_retries=2)
        if not html:
            return { "npcID": npc_id, "mapID": None, "mapName": None, "x": None, "y": None, "error": True }
        m = re.findall(r"g_mapperData\s*=\s*(\{.*?\});", html)
        if m:
            data = json.loads(m[0])
            for zid, pts in data.items():
                if pts and len(pts) > 0:
                    p0 = pts[0]
                    coords_list = p0.get("coords", [])
                    c = coords_list[0] if coords_list else None
                    if c and len(c) == 2:
                        return {
                            "npcID": npc_id,
                            "mapID": p0.get("uiMapId"),
                            "mapName": p0.get("uiMapName", "").lower(),
                            "x": round(c[0] / 100.0, 4),
                            "y": round(c[1] / 100.0, 4),
                        }
        return { "npcID": npc_id, "mapID": None, "mapName": None, "x": None, "y": None, "no_coords": True }
    except Exception:
        return { "npcID": npc_id, "mapID": None, "mapName": None, "x": None, "y": None, "error": True }

def fetch_zone_name(zone_id: int) -> dict:
    url = f"https://www.wowhead.com/forever/zone={zone_id}"
    try:
        html = fetch_url(url, timeout=8, max_retries=2)
        if not html:
            return {"zoneID": zone_id, "name": None, "error": True}
        m = re.search(r"<title>(.*?)\s*-\s*Zone", html, re.I)
        if m:
            z_name = m.group(1).strip().lower()
            return {"zoneID": zone_id, "name": z_name}
        return {"zoneID": zone_id, "name": None, "no_title": True}
    except Exception:
        return {"zoneID": zone_id, "name": None, "error": True}

def fetch_recipe_item_rep_and_spec(item_id: int) -> tuple:
    url = f"https://www.wowhead.com/forever/item={item_id}&xml"
    try:
        xml = fetch_url(url, timeout=8, max_retries=2)
        if not xml:
            return item_id, {"error": True}
        m_rep = re.search(r'Requires\s+(?:<[^>]+>)?([^<]+)(?:</[^>]+>)?\s*-\s*(Neutral|Friendly|Honored|Revered|Exalted)', xml, re.I)
        m_spec = re.search(r'Requires\s+(?:<[^>]+>)?((?:Gnomish|Goblin)\s+Engineer|(?:Tribal|Elemental|Dragonscale)\s+Leatherworking|(?:Armorsmith|Weaponsmith|Axesmith|Hammersmith|Swordsmith|Master\s+Axesmith|Master\s+Swordsmith|Master\s+Hammersmith))', xml, re.I)
        rep_faction = m_rep.group(1).strip().lower() if m_rep else None
        rep_standing = m_rep.group(2).strip().lower() if m_rep else None
        spec = m_spec.group(1).strip().lower() if m_spec else None
        return item_id, {
            "faction": rep_faction,
            "standing": rep_standing,
            "spec": spec,
        }
    except Exception as e:
        return item_id, {"error": str(e)}

def find_matching_spell(item_name: str, spells_by_norm: dict) -> dict:
    """Finds the craft spell corresponding to a recipe scroll item, handling suffixes and naming variations."""
    nk = norm_key(item_name)
    if not nk:
        return None

    # 1. Direct normalized key
    if nk in spells_by_norm:
        return spells_by_norm[nk]

    # 2. Known manual alias
    if nk in MANUAL_ALIASES and MANUAL_ALIASES[nk] in spells_by_norm:
        return spells_by_norm[MANUAL_ALIASES[nk]]

    # 3. Singular / plural variation (strip or append 's')
    if nk.endswith("s") and nk[:-1] in spells_by_norm:
        return spells_by_norm[nk[:-1]]
    if (nk + "s") in spells_by_norm:
        return spells_by_norm[nk + "s"]

    # 4. Suffix variations (potion, elixir, oil, etc.)
    for sfx in ["potion", "elixir", "oil", "transmutation"]:
        if (nk + sfx) in spells_by_norm:
            return spells_by_norm[nk + sfx]

    return None

def sync(prof_list: list = None, refresh: bool = False, skip_npcs: bool = False, dry_run: bool = False, verbose: bool = False, check_only: bool = False, enrich_rep: bool = False):
    os.makedirs(DATA_DIR, exist_ok=True)
    
    # 1. Load or initialize scrape cache
    raw_cache = {}
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                raw_cache = json.load(f)
        except Exception:
            raw_cache = {}

    # 2. Load or initialize NPC cache
    npc_cache = {}
    if os.path.exists(NPC_CACHE_FILE):
        try:
            with open(NPC_CACHE_FILE, "r", encoding="utf-8") as f:
                npc_cache = json.load(f)
        except Exception:
            npc_cache = {}

    # 2.1 Load or initialize Zone cache
    zone_cache = {str(k): v for k, v in WOWHEAD_ZONES.items()}
    if os.path.exists(ZONE_CACHE_FILE):
        try:
            with open(ZONE_CACHE_FILE, "r", encoding="utf-8") as f:
                loaded_zones = json.load(f)
                zone_cache.update(loaded_zones)
        except Exception:
            pass

    # 2.2 Load or initialize Reputation & Spec cache
    rep_cache = {}
    if os.path.exists(REP_CACHE_FILE):
        try:
            with open(REP_CACHE_FILE, "r", encoding="utf-8") as f:
                rep_cache = json.load(f)
        except Exception:
            rep_cache = {}

    if prof_list:
        invalid = [p for p in prof_list if p not in PROFESSIONS]
        if invalid:
            print(f"Warning: Unknown profession(s): {', '.join(invalid)}", file=sys.stderr)
        selected_profs = [p for p in prof_list if p in PROFESSIONS]
    else:
        selected_profs = list(PROFESSIONS.keys())

    if not selected_profs:
        print(f"Error: No valid professions to sync. Supported: {', '.join(PROFESSIONS.keys())}", file=sys.stderr)
        return

    # 3. Fetch/Refresh raw data for selected professions (with cache self-healing)
    cache_dirty = False

    # Prune any existing legacy cache entries to reduce file size
    if raw_cache:
        for p_key, entry in raw_cache.items():
            if isinstance(entry, dict):
                orig_sp_len = len(entry.get("spells", []))
                entry["spells"] = [compact_spell(sp) for sp in entry.get("spells", [])]
                entry["items"] = [compact_item(it) for it in entry.get("items", [])]
        cache_dirty = True

    for p in selected_profs:
        p_info = PROFESSIONS.get(p)
        if not p_info:
            continue
        
        cached_entry = raw_cache.get(p, {})
        needs_fetch = refresh or not cached_entry or not cached_entry.get("spells") or not cached_entry.get("items")
        
        if needs_fetch:
            print(f"Fetching {p} from Wowhead Forever...")
            spells = fetch_spells_for_profession(p, p_info)
            time.sleep(0.2)
            items = fetch_recipe_items_for_profession(p)
            time.sleep(0.2)

            if spells or items:
                raw_cache[p] = {
                    "spells": spells if spells else cached_entry.get("spells", []),
                    "items": items if items else cached_entry.get("items", []),
                    "fetched_at": int(time.time()),
                }
                cache_dirty = True
                print(f"  -> {len(raw_cache[p]['spells'])} spells, {len(raw_cache[p]['items'])} recipe items")
            else:
                print(f"  Warning: No data returned for {p}; retaining previous cache if available.", file=sys.stderr)

    if cache_dirty and not dry_run and not check_only:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(raw_cache, f, indent=2)

    # 4. Collect unique NPC IDs from recipe items and spells across all cached professions
    needed_npcs = set()
    for p in PROFESSIONS.keys():
        p_data = raw_cache.get(p, {})
        for it in p_data.get("items", []):
            for sm in it.get("sourcemore", []):
                if sm.get("t") == 1 and sm.get("ti"):
                    needed_npcs.add(sm.get("ti"))
        for sp in p_data.get("spells", []):
            for sm in sp.get("sourcemore", []):
                if sm.get("t") == 1 and sm.get("ti"):
                    needed_npcs.add(sm.get("ti"))

    missing_npcs = [nid for nid in needed_npcs if str(nid) not in npc_cache]
    if verbose:
        print(f"Unique NPCs referenced: {len(needed_npcs)} ({len(missing_npcs)} need location lookup)")

    if missing_npcs and not skip_npcs and not dry_run and not check_only:
        print(f"Fetching coordinates for {len(missing_npcs)} NPCs in parallel...")
        npc_cache_dirty = False
        with ThreadPoolExecutor(max_workers=5) as executor:
            results = executor.map(fetch_npc_location, missing_npcs)
            for res in results:
                nid = res["npcID"]
                # Only cache if valid coordinates or confirmed without coords; do not cache transient errors
                if not res.get("error"):
                    npc_cache[str(nid)] = res
                    npc_cache_dirty = True
                    if verbose and res.get("mapID"):
                        print(f"  NPC {nid:6d}: {res.get('mapName')} ({res.get('x')}, {res.get('y')})")

        if npc_cache_dirty:
            with open(NPC_CACHE_FILE, "w", encoding="utf-8") as f:
                json.dump(npc_cache, f, indent=2)

    # 4.1 Collect unique Zone IDs and resolve any new/unknown zones (e.g. Camelot additions)
    needed_zones = set()
    for p in PROFESSIONS.keys():
        p_data = raw_cache.get(p, {})
        for it in p_data.get("items", []):
            for sm in it.get("sourcemore", []):
                if sm.get("z"):
                    needed_zones.add(sm.get("z"))
        for sp in p_data.get("spells", []):
            for sm in sp.get("sourcemore", []):
                if sm.get("z"):
                    needed_zones.add(sm.get("z"))

    missing_zones = [zid for zid in needed_zones if str(zid) not in zone_cache and zid not in zone_cache]
    if missing_zones and not dry_run and not check_only:
        print(f"Resolving names for {len(missing_zones)} new zone IDs...")
        zone_cache_dirty = False
        for zid in missing_zones:
            res = fetch_zone_name(zid)
            time.sleep(0.3)
            if res.get("name"):
                zone_cache[str(zid)] = res["name"]
                zone_cache_dirty = True
                if verbose:
                    print(f"  Zone {zid}: {res['name']}")
        if zone_cache_dirty:
            with open(ZONE_CACHE_FILE, "w", encoding="utf-8") as f:
                json.dump(zone_cache, f, indent=2, sort_keys=True)
    elif not os.path.exists(ZONE_CACHE_FILE) and not dry_run and not check_only:
        with open(ZONE_CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(zone_cache, f, indent=2, sort_keys=True)

    # 4.2 Enrich missing reputation / specialization requirements (opt-in with --enrich-rep)
    if enrich_rep and not dry_run and not check_only:
        needed_rep_items = set()
        for p in PROFESSIONS.keys():
            p_data = raw_cache.get(p, {})
            for it in p_data.get("items", []):
                item_id = it.get("id")
                item_srcs = it.get("source") or []
                if item_id and (5 in item_srcs or it.get("sourcemore")):
                    needed_rep_items.add(item_id)

        missing_rep_items = [iid for iid in needed_rep_items if str(iid) not in rep_cache and iid not in rep_cache]
        if missing_rep_items:
            print(f"Checking reputation/spec requirements for {len(missing_rep_items)} recipe items...")
            rep_cache_dirty = False
            for iid in missing_rep_items:
                res_id, res = fetch_recipe_item_rep_and_spec(iid)
                time.sleep(0.15)
                if not res.get("error"):
                    rep_cache[str(res_id)] = res
                    rep_cache_dirty = True
                    if verbose and (res.get("faction") or res.get("spec")):
                        print(f"  Item {res_id}: faction={res.get('faction')}, standing={res.get('standing')}, spec={res.get('spec')}")
            if rep_cache_dirty:
                with open(REP_CACHE_FILE, "w", encoding="utf-8") as f:
                    json.dump(rep_cache, f, indent=2, sort_keys=True)

    # 5. Construct unified recipes database
    # Safe compilation: always compile across all cached professions to prevent accidental truncation
    unified_recipes = {}
    item_to_spell = {}
    output_to_spell = {}

    for p, p_info in PROFESSIONS.items():
        p_data = raw_cache.get(p, {})
        if not p_data.get("spells"):
            continue
        skill_id = p_info["skillID"]

        # Build fast lookup for spells in this profession
        spells_by_norm = {}
        for sp in p_data.get("spells", []):
            sp_norm = norm_key(sp.get("name", ""))
            if sp_norm and sp_norm not in spells_by_norm:
                spells_by_norm[sp_norm] = sp

        # Map recipe items to spells
        item_by_spell_id = {}
        for it in p_data.get("items", []):
            matched_spell = find_matching_spell(it.get("name", ""), spells_by_norm)
            if matched_spell:
                item_by_spell_id[matched_spell["id"]] = it

        prof_candidates = {}
        for sp in p_data.get("spells", []):
            spell_id = sp.get("id")
            if not spell_id:
                continue

            # Skip invalid / datamined / retail spells:
            # - Spells with rank containing "Tier " (modern retail / player housing)
            # - Spells with min_skill >= 1000 (dummy spells e.g. 9999)
            rank = sp.get("rank")
            if rank and "tier" in str(rank).lower():
                continue

            min_skill = sp.get("learnedat")
            if min_skill is not None and min_skill >= 1000:
                continue

            name = sp.get("name", "").strip()
            colors = sp.get("colors")
            creates = sp.get("creates")
            out_item_id = creates[0] if (creates and len(creates) > 0) else None
            training_cost = sp.get("trainingcost")

            # Reagents
            raw_reagents = sp.get("reagents") or []
            reagents = {}
            for r in raw_reagents:
                if len(r) >= 2:
                    reagents[int(r[0])] = int(r[1])

            # Skip non-crafting skill headers, specializations, and dummy spells (e.g. "Blacksmithing", "Disenchant")
            if not reagents and not out_item_id:
                continue

            # Associated recipe scroll item
            recipe_item = item_by_spell_id.get(spell_id)
            recipe_item_id = recipe_item.get("id") if recipe_item else None
            recipe_item_name = recipe_item.get("name") if recipe_item else None

            # Resolve sources
            sources = []
            raw_sources = sp.get("source") or []

            # 1. Sources from recipe item if taught via item
            if recipe_item:
                item_sources = recipe_item.get("source") or []
                sm_list = recipe_item.get("sourcemore") or []

                for sm in sm_list:
                    sm_type = sm.get("t")
                    sm_id = sm.get("ti")
                    sm_name = sm.get("n", "").strip()
                    z_id = sm.get("z")
                    zone_name = zone_cache.get(str(z_id)) or zone_cache.get(z_id)

                    if sm_type == 1: # NPC
                        npc_loc = npc_cache.get(str(sm_id), {})
                        z = npc_loc.get("mapName") or zone_name
                        s_type = "vendor" if (5 in item_sources) else ("drop" if (2 in item_sources) else "trainer")
                        s_record = {
                            "type": s_type,
                            "name": sm_name.lower(),
                            "npcID": sm_id,
                            "zone": z,
                            "mapID": npc_loc.get("mapID"),
                            "x": npc_loc.get("x"),
                            "y": npc_loc.get("y"),
                        }
                        sources.append(s_record)
                    elif sm_type == 2: # GameObject / Cache / Chest
                        s_record = {
                            "type": "object",
                            "name": sm_name.lower() if sm_name else "chest / container",
                            "zone": zone_name,
                        }
                        sources.append(s_record)
                    elif sm_type == 3: # Item container / Pickpocket Lockbox
                        name_lower = sm_name.lower() if sm_name else "container"
                        is_pickpocket = any(k in name_lower for k in ("junkbox", "lockbox", "clippings", "pocket", "strongbox", "footlocker"))
                        s_record = {
                            "type": "pickpocket" if is_pickpocket else "container",
                            "name": name_lower,
                            "zone": zone_name,
                        }
                        sources.append(s_record)
                    elif sm_type == 5: # Quest
                        s_record = {
                            "type": "quest",
                            "name": sm_name.lower(),
                            "questID": sm_id,
                            "zone": zone_name,
                        }
                        sources.append(s_record)
                    elif zone_name:
                        s_record = {
                            "type": "drop",
                            "name": "zone drop",
                            "zone": zone_name,
                        }
                        sources.append(s_record)


                if not sources:
                    if 5 in item_sources:
                        sources.append({ "type": "vendor", "desc": "vendor" })
                    elif 2 in item_sources:
                        sources.append({ "type": "drop", "desc": "world / creature drop" })
                    elif 4 in item_sources:
                        sources.append({ "type": "quest", "desc": "quest reward" })
                    elif 16 in item_sources:
                        sources.append({ "type": "event", "desc": "world event" })
                    elif 6 in item_sources:
                        sources.append({ "type": "trainer", "desc": "trainer" })
                    else:
                        sources.append({ "type": "vendor" if recipe_item.get("buyprice") else "drop", "desc": "vendor / drop" })
            else:
                # 2. Directly taught by trainer (no scroll)
                s_rec = {
                    "type": "trainer",
                    "desc": "trainer",
                }
                if training_cost and training_cost > 0:
                    s_rec["cost"] = int(training_cost)
                sources.append(s_rec)

            rec_data = {
                "id": spell_id,
                "name": name.lower(),
                "skillID": skill_id,
                "minSkill": min_skill,
                "colors": colors,
                "output": out_item_id,
                "reagents": reagents,
                "recipeItemID": recipe_item_id,
                "recipeItemName": recipe_item_name,
                "sources": sources,
            }

            if spell_id in EVENT_MAP:
                rec_data["isEvent"] = True
                rec_data["event"] = EVENT_MAP[spell_id]

            if spell_id in SPECIALIZATION_RECIPES:
                rec_data["spec"] = SPECIALIZATION_RECIPES[spell_id]
            elif recipe_item_id and str(recipe_item_id) in rep_cache:
                dyn_spec = rep_cache[str(recipe_item_id)].get("spec")
                if dyn_spec:
                    rec_data["spec"] = dyn_spec

            # Reputation recipe enrichment (by spell_id, recipe_item_id, or dynamic rep_cache)
            rep_info = REPUTATION_RECIPES.get(spell_id)
            if not rep_info and recipe_item_id:
                rep_info = REPUTATION_RECIPES.get(recipe_item_id)
            if not rep_info and recipe_item_id and str(recipe_item_id) in rep_cache:
                dyn_rep = rep_cache[str(recipe_item_id)]
                if dyn_rep.get("faction") and dyn_rep.get("standing"):
                    rep_info = {
                        "faction": dyn_rep["faction"],
                        "standing": dyn_rep["standing"],
                    }

            if rep_info:
                rec_data["faction"] = rep_info["faction"]
                rec_data["standing"] = rep_info["standing"]
                matched_vendor = False
                for s in sources:
                    if s.get("type") == "vendor":
                        s["faction"] = rep_info["faction"]
                        s["standing"] = rep_info["standing"]
                        if rep_info.get("tokens"):
                            s["tokens"] = rep_info["tokens"]
                        matched_vendor = True
                if not matched_vendor and rep_info.get("npcName"):
                    s_rec = {
                        "type": "vendor",
                        "name": rep_info["npcName"].lower(),
                        "npcID": rep_info.get("npcID"),
                        "zone": rep_info.get("zone"),
                        "mapID": rep_info.get("mapID"),
                        "x": rep_info.get("x"),
                        "y": rep_info.get("y"),
                        "faction": rep_info["faction"],
                        "standing": rep_info["standing"],
                    }
                    if rep_info.get("tokens"):
                        s_rec["tokens"] = rep_info["tokens"]
                    sources.append(s_rec)

            # Unique encounter mechanics overrides
            if spell_id in UNIQUE_ENCOUNTER_SOURCES:
                sources = list(UNIQUE_ENCOUNTER_SOURCES[spell_id])
                rec_data["sources"] = sources

            norm_n = name.lower()
            prof_candidates.setdefault(norm_n, []).append(rec_data)

        # Select canonical recipe for each unique name in this profession
        for norm_n, candidates in prof_candidates.items():
            if len(candidates) == 1:
                chosen = candidates[0]
            else:
                # Score candidates to select authentic classic version
                def candidate_score(c):
                    score = 0
                    sid = c["id"]
                    # Authentic Classic spell IDs are typically < 100,000 (give huge preference over 400k+ SoD/datamined duplicates)
                    if sid < 100000:
                        score += 10000
                    if c.get("recipeItemID"):
                        score += 1000
                    if c.get("output"):
                        score += 500
                    if c.get("spec"):
                        score += 100
                    if c.get("faction"):
                        score += 100
                    if c.get("sources"):
                        for s in c["sources"]:
                            if s.get("mapID") and s.get("x") is not None:
                                score += 100
                                break
                            elif s.get("name") and s["name"] not in ["trainer", "world / creature drop"]:
                                score += 50
                    return score


                chosen = max(candidates, key=lambda c: (candidate_score(c), -c["id"]))

            sid = chosen["id"]
            unified_recipes[sid] = chosen
            if chosen.get("recipeItemID"):
                item_to_spell[chosen["recipeItemID"]] = sid
            if chosen.get("output"):
                output_to_spell[chosen["output"]] = sid


    # 6. Detailed summary statistics
    source_counts = {"trainer": 0, "vendor": 0, "drop": 0, "quest": 0, "other": 0}
    with_coords = 0
    with_cost = 0
    for r in unified_recipes.values():
        for s in r.get("sources", []):
            st = s.get("type", "other")
            source_counts[st] = source_counts.get(st, 0) + 1
            if s.get("mapID") and s.get("x") is not None:
                with_coords += 1
            if s.get("cost"):
                with_cost += 1

    print("\n--- SFUI Recipe Database Summary ---")
    print(f"Total Crafting Recipes: {len(unified_recipes)}")
    for p in PROFESSIONS:
        count = sum(1 for r in unified_recipes.values() if r["skillID"] == PROFESSIONS[p]["skillID"])
        print(f"  {p:15s}: {count:4d} recipes")
    print("\nSource Breakdown:")
    print(f"  Trainers:                  {source_counts.get('trainer', 0):4d} ({with_cost} with exact training cost)")
    print(f"  Vendors:                   {source_counts.get('vendor', 0):4d}")
    print(f"  Creature / World Drops:    {source_counts.get('drop', 0):4d}")
    print(f"  Quests:                    {source_counts.get('quest', 0):4d}")
    print(f"  With Exact Map Waypoints:  {with_coords:4d}")
    print(f"\nCross-Index Mappings:")
    print(f"  Recipe Scroll Items -> Spells:   {len(item_to_spell):4d}")
    print(f"  Crafted Output Items -> Spells:  {len(output_to_spell):4d}")

    # Check-only mode: compare with existing file and report
    if check_only:
        if os.path.exists(LUA_TARGET):
            size_kb = os.path.getsize(LUA_TARGET) / 1024
            print(f"\n[Check] {os.path.relpath(LUA_TARGET, REPO_ROOT)} exists ({size_kb:.1f} KB).")
        else:
            print(f"\n[Check] {os.path.relpath(LUA_TARGET, REPO_ROOT)} does NOT exist.")
        return

    if dry_run:
        print("\n[Dry Run] Skipping file generation.")
        return

    # 7. Safety Threshold: prevent overwriting good database on network/scraping failure
    if len(unified_recipes) < 2000:
        print(f"Error: Unified recipe count ({len(unified_recipes)}) below safety threshold (2000). Aborting to prevent data corruption.", file=sys.stderr)
        return

    # 8. Write data/recipes_camelot.lua (Atomic write via .tmp file)
    # Pre-index by skillID and pool shared source lists to minimize memory churn & file size
    skill_to_spells = {}
    source_usage = {}
    for sid, r in unified_recipes.items():
        sk = r["skillID"]
        skill_to_spells.setdefault(sk, []).append(sid)
        if r.get("sources"):
            key = json.dumps(r["sources"], sort_keys=True)
            source_usage[key] = source_usage.get(key, 0) + 1

    source_pool = {} # json_str -> pool_id
    pool_counter = 1
    for key, count in sorted(source_usage.items(), key=lambda x: -x[1]):
        if count >= 2:
            source_pool[key] = pool_counter
            pool_counter += 1

    temp_target = LUA_TARGET + ".tmp"
    print(f"\nWriting {os.path.relpath(temp_target, REPO_ROOT)}...")
    with open(temp_target, "w", encoding="utf-8") as f:
        f.write("local addonName, addon = ...\n")
        f.write("---@diagnostic disable: undefined-global, undefined-field\n")
        f.write("sfui = sfui or {}\n")
        f.write("sfui.recipes_camelot = sfui.recipes_camelot or {}\n\n")
        f.write("-- ══════════════════════════════════════════════════════════════════════════════\n")
        f.write("--  sfui/data/recipes_camelot.lua\n")
        f.write("--  Authoritative Recipe & Source database for Camelot / Classic Forever.\n")
        f.write("--  Generated automatically via scripts/sync-recipes.py from Wowhead Forever.\n")
        f.write("-- ══════════════════════════════════════════════════════════════════════════════\n\n")

        # Emit shared source pool
        f.write("-- Shared source tables pool (deduplicated to optimize memory footprint)\n")
        f.write("local SRC_POOL = {\n")
        # Invert source_pool to iterate by pool_id
        id_to_sources = {pid: json.loads(key) for key, pid in source_pool.items()}
        for pid in sorted(id_to_sources.keys()):
            sources_list = id_to_sources[pid]
            f.write(f"    [{pid}] = {{\n")
            for s in sources_list:
                parts = [f'type = "{s["type"]}"']
                if s.get("name"):
                    parts.append(f'name = "{escape_lua_str(s["name"])}"')
                if s.get("desc") and s.get("desc") != s.get("type"):
                    parts.append(f'desc = "{escape_lua_str(s["desc"])}"')
                if s.get("cost") and s["cost"] > 0:
                    parts.append(f'cost = {s["cost"]}')
                if s.get("npcID"):
                    parts.append(f'npcID = {s["npcID"]}')
                if s.get("questID"):
                    parts.append(f'questID = {s["questID"]}')
                if s.get("zone"):
                    parts.append(f'zone = "{escape_lua_str(s["zone"])}"')
                if s.get("faction"):
                    parts.append(f'faction = "{escape_lua_str(s["faction"])}"')
                if s.get("standing"):
                    parts.append(f'standing = "{escape_lua_str(s["standing"])}"')
                if s.get("tokens"):
                    parts.append(f'tokens = "{escape_lua_str(s["tokens"])}"')
                if s.get("mapID") and s["mapID"] > 0:
                    parts.append(f'mapID = {s["mapID"]}')
                    if s.get("x") is not None and s.get("y") is not None:
                        x, y = s["x"], s["y"]
                        if 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0:
                            parts.append(f'x = {x:.4f}, y = {y:.4f}')
                f.write(f'        {{ {", ".join(parts)} }},\n')
            f.write("    },\n")
        f.write("}\n\n")

        f.write("sfui.recipes_camelot.recipes = {\n")
        for sid in sorted(unified_recipes.keys()):
            r = unified_recipes[sid]
            f.write(f"    [{sid}] = {{\n")
            f.write(f"        id = {sid},\n")
            f.write(f'        name = "{escape_lua_str(r["name"])}",\n')
            f.write(f'        skillID = {r["skillID"]},\n')
            if r["minSkill"] is not None:
                f.write(f'        minSkill = {r["minSkill"]},\n')
            if r["colors"] and len(r["colors"]) == 4:
                c = r["colors"]
                f.write(f'        colors = {{ {c[0]}, {c[1]}, {c[2]}, {c[3]} }},\n')
            if r["output"]:
                f.write(f'        output = {r["output"]},\n')
            if r["recipeItemID"]:
                f.write(f'        recipeItemID = {r["recipeItemID"]},\n')
            if r.get("isEvent"):
                f.write('        isEvent = true,\n')
                f.write(f'        event = "{escape_lua_str(r["event"])}",\n')
            if r.get("spec"):
                f.write(f'        spec = "{escape_lua_str(r["spec"])}",\n')
            if r.get("faction"):
                f.write(f'        faction = "{escape_lua_str(r["faction"])}",\n')
            if r.get("standing"):
                f.write(f'        standing = "{escape_lua_str(r["standing"])}",\n')

            # Reagents
            if r["reagents"]:
                reags = ", ".join([f"[{k}] = {v}" for k, v in sorted(r["reagents"].items())])
                f.write(f'        reagents = {{ {reags} }},\n')

            # Sources with coordinate bounds validation and training costs
            if r["sources"]:
                key = json.dumps(r["sources"], sort_keys=True)
                if key in source_pool:
                    f.write(f"        sources = SRC_POOL[{source_pool[key]}],\n")
                else:
                    f.write("        sources = {\n")
                    for s in r["sources"]:
                        parts = [f'type = "{s["type"]}"']
                        if s.get("name"):
                            parts.append(f'name = "{escape_lua_str(s["name"])}"')
                        if s.get("desc") and s.get("desc") != s.get("type"):
                            parts.append(f'desc = "{escape_lua_str(s["desc"])}"')
                        if s.get("cost") and s["cost"] > 0:
                            parts.append(f'cost = {s["cost"]}')
                        if s.get("npcID"):
                            parts.append(f'npcID = {s["npcID"]}')
                        if s.get("questID"):
                            parts.append(f'questID = {s["questID"]}')
                        if s.get("zone"):
                            parts.append(f'zone = "{escape_lua_str(s["zone"])}"')
                        if s.get("faction"):
                            parts.append(f'faction = "{escape_lua_str(s["faction"])}"')
                        if s.get("standing"):
                            parts.append(f'standing = "{escape_lua_str(s["standing"])}"')
                        if s.get("tokens"):
                            parts.append(f'tokens = "{escape_lua_str(s["tokens"])}"')
                        if s.get("mapID") and s["mapID"] > 0:
                            parts.append(f'mapID = {s["mapID"]}')
                            if s.get("x") is not None and s.get("y") is not None:
                                x, y = s["x"], s["y"]
                                if 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0:
                                    parts.append(f'x = {x:.4f}, y = {y:.4f}')
                        f.write(f'            {{ {", ".join(parts)} }},\n')
                    f.write("        },\n")

            f.write("    },\n")
        f.write("}\n\n")

        # Item mapping (scroll -> spellID)
        f.write("sfui.recipes_camelot.items = {\n")
        for iid in sorted(item_to_spell.keys()):
            f.write(f"    [{iid}] = {item_to_spell[iid]},\n")
        f.write("}\n\n")

        # Output mapping (crafted item -> spellID)
        f.write("sfui.recipes_camelot.outputs = {\n")
        for oid in sorted(output_to_spell.keys()):
            f.write(f"    [{oid}] = {output_to_spell[oid]},\n")
        f.write("}\n\n")

        # Pre-indexed skill mapping (skillID -> spellIDs list)
        f.write("sfui.recipes_camelot.by_skill = {\n")
        for sk in sorted(skill_to_spells.keys()):
            sids = sorted(skill_to_spells[sk])
            f.write(f"    [{sk}] = {{ {', '.join(str(s) for s in sids)} }},\n")
        f.write("}\n")

    # 8.1 Validate syntax with luac before atomically swapping
    print("Validating Lua syntax...")
    try:
        subprocess.run(["luac", "-p", temp_target], check=True, capture_output=True, text=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        err_msg = getattr(e, "stderr", str(e))
        print(f"Error: Generated Lua failed syntax validation: {err_msg}", file=sys.stderr)
        if os.path.exists(temp_target):
            os.remove(temp_target)
        return

    # Atomic rename (POSIX safe)
    os.replace(temp_target, LUA_TARGET)
    file_size_kb = os.path.getsize(LUA_TARGET) / 1024
    print(f"Atomically updated {os.path.relpath(LUA_TARGET, REPO_ROOT)} successfully ({file_size_kb:.1f} KB).")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Synchronize recipe database from Wowhead Forever.")
    parser.add_argument("--refresh", action="store_true", help="Force re-fetching all pages from Wowhead.")
    parser.add_argument("--professions", type=str, help="Comma-separated list of professions to sync.")
    parser.add_argument("--skip-npcs", action="store_true", help="Skip fetching NPC map coordinates.")
    parser.add_argument("--dry-run", action="store_true", help="Parse and log without modifying files.")
    parser.add_argument("--check", action="store_true", help="Check database status without writing files.")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose log output.")
    parser.add_argument("--enrich-rep", action="store_true", help="Fetch tooltip XML for reputation and specialization requirements.")
    args = parser.parse_args()

    profs = [p.strip().lower() for p in args.professions.split(",")] if args.professions else None
    sync(prof_list=profs, refresh=args.refresh, skip_npcs=args.skip_npcs, dry_run=args.dry_run, verbose=args.verbose, check_only=args.check, enrich_rep=args.enrich_rep)
