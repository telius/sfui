#!/usr/bin/env python3
"""
SFUI Unified Data Synchronizer (Camelot / Classic Forever)
Single authoritative runner that orchestrates all SFUI data pipelines using the shared `sync_core` engine:
  1. zones     — Auto-discovers new Forever open-world zones, dungeons & raids -> data/forever_zones.json
  2. dj        — Synchronizes Dungeon Journal boss loot, drop rates & quests    -> data/dj_camelot.lua
  3. recipes   — Synchronizes all 11 professions, recipes, reagents & sources   -> data/recipes_camelot.lua
  4. fishing   — Synchronizes Fishing Atlas species, waters, pools & habitats   -> data/fishing_camelot.lua
  5. bonusroll — Synchronizes Retail Bonus Roll chest database (DB2 & Wowhead)  -> frames/gear/bonusroll.lua

Usage:
    python3 scripts/sync-data.py [--only zones,dj,recipes,fishing,bonusroll] [--refresh] [--dry-run] [--verbose]
"""

import argparse
import importlib.util
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from sync_core import load_forever_zones


def _load_script_module(module_name: str, filename: str):
    path = os.path.join(SCRIPT_DIR, filename)
    spec = importlib.util.spec_from_file_location(module_name, path)
    if not spec or not spec.loader:
        raise RuntimeError(f"Could not load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def run_unified_sync(
    targets: list[str] | None = None,
    refresh: bool = False,
    refresh_classic: bool = False,
    dry_run: bool = False,
    check_only: bool = False,
    verbose: bool = False,
):
    valid_targets = ("zones", "dj", "recipes", "fishing", "bonusroll")
    default_targets = ("zones", "dj", "recipes", "fishing")
    if not targets:
        active_targets = list(default_targets)
    elif "all" in targets:
        active_targets = list(valid_targets)
    else:
        active_targets = [t for t in valid_targets if t in targets]

    t0 = time.time()
    print("=================================================================")
    print(f" SFUI Unified Data Synchronizer — Targets: {', '.join(active_targets)}")
    print("=================================================================")

    # 1. Zone / Dungeon / Raid Discovery (always loaded so downstream modules have latest forever_zones.json)
    if any(t in active_targets for t in ("zones", "dj", "recipes", "fishing")):
        refresh_zones = refresh and ("zones" in active_targets or len(active_targets) > 1)
        zones = load_forever_zones(refresh=refresh_zones, verbose=verbose)
        if "zones" in active_targets:
            open_zones = sum(1 for z in zones.values() if z.get("category") in (0, 1))
            instances = sum(1 for z in zones.values() if z.get("category") in (2, 3))
            print(f"[1/5 Zones] Verified {len(zones)} Forever zones ({open_zones} open-world, {instances} dungeons/raids).")

    # 2. Dungeon Journal Loot, Drop Rates & Quests
    if "dj" in active_targets:
        print("\n-----------------------------------------------------------------")
        print(" [2/5 Dungeon Journal] Synchronizing boss loot, drop rates & quests")
        print("-----------------------------------------------------------------")
        dj_mod = _load_script_module("sync_dj_loot", "sync-dj-loot.py")
        dj_mod.sync_dj(
            refresh_rates=refresh,
            refresh_quests=refresh,
            refresh_guide=refresh,
            refresh_classic=refresh_classic,
            check_guide=check_only,
            dry_run=dry_run,
            verbose=verbose,
        )

    # 3. Professions & Recipes
    if "recipes" in active_targets:
        print("\n-----------------------------------------------------------------")
        print(" [3/5 Recipes] Synchronizing profession crafts, reagents & sources")
        print("-----------------------------------------------------------------")
        recipes_mod = _load_script_module("sync_recipes", "sync-recipes.py")
        recipes_mod.sync(
            prof_list=None,
            refresh=refresh,
            skip_npcs=False,
            dry_run=dry_run,
            verbose=verbose,
            check_only=check_only,
            enrich_rep=False,
        )

    # 4. Fishing Atlas & Waters
    if "fishing" in active_targets:
        print("\n-----------------------------------------------------------------")
        print(" [4/5 Fishing] Synchronizing fish species, waters, pools & habitats")
        print("-----------------------------------------------------------------")
        fishing_mod = _load_script_module("sync_fishing", "sync-fishing.py")
        fishing_mod.sync_fishing(
            refresh=refresh,
            refresh_classic=refresh_classic,
            dry_run=dry_run,
            verbose=verbose,
        )

    # 5. Retail Bonus Roll Chest Database
    if "bonusroll" in active_targets:
        print("\n-----------------------------------------------------------------")
        print(" [5/5 Bonus Roll] Synchronizing Retail chest database (DB2 & Wowhead)")
        print("-----------------------------------------------------------------")
        br_mod = _load_script_module("sync_bonusroll", "sync-bonusroll.py")
        br_mod.sync_bonusroll(
            dry_run=dry_run or check_only,
            verbose=verbose,
        )

    dt = time.time() - t0
    print("\n=================================================================")
    print(f" SFUI Unified Data Sync Complete in {dt:.2f}s")
    print("=================================================================")


def main():
    parser = argparse.ArgumentParser(description="SFUI Unified Data Synchronizer (Zones, DJ, Recipes, Fishing).")
    parser.add_argument(
        "targets",
        nargs="*",
        help="Optional target subset: all, zones, dj, zones-dj, recipes, fishing, bonusroll (default: zones,dj,recipes,fishing).",
    )
    parser.add_argument(
        "--only",
        type=str,
        default="",
        help="Comma- or hyphen-separated list of targets to run (e.g. zones-dj, recipes, fishing).",
    )
    parser.add_argument(
        "--refresh",
        "--refresh-all",
        dest="refresh",
        action="store_true",
        help="Force live re-fetch of Forever data from Wowhead endpoints.",
    )
    parser.add_argument(
        "--refresh-classic",
        action="store_true",
        help="Also force re-fetching already-cached Classic 1.12 bosses, quests, and zones.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Verify and preview without modifying Lua files.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Audit/check caches without modifying Lua files.",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose output.",
    )

    args = parser.parse_args()
    target_set = set()
    raw_parts = list(args.targets)
    if args.only:
        raw_parts.append(args.only)
    for item in raw_parts:
        for part in item.replace("-", ",").split(","):
            if part.strip():
                target_set.add(part.strip().lower())

    run_unified_sync(
        targets=sorted(target_set) if target_set else None,
        refresh=args.refresh or args.refresh_classic,
        refresh_classic=args.refresh_classic,
        dry_run=args.dry_run,
        check_only=args.check,
        verbose=args.verbose,
    )


if __name__ == "__main__":
    main()

