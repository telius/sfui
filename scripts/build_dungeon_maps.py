#!/usr/bin/env python3
"""Build the sfui_dungeon_maps companion addon: DXT1/DXT5 BLP2 textures and Classic map patch table."""
import os
import re
import struct
import subprocess
from pathlib import Path
from PIL import Image

REPO_ROOT = Path("/home/james/projects/sfui")
SRC_MEDIA = REPO_ROOT / "media" / "dungeonmaps"
FDJ_ROOT = Path("/home/james/Games/World of Warcraft/_forever_/Interface/AddOns/ForeverDungeonJournal")
FDJ_JOURNAL = FDJ_ROOT / "Core" / "Journal.lua"
FDJ_PATCHES = FDJ_ROOT / "Media" / "MapPatches"
OM_DRAWN = Path("/home/james/Games/World of Warcraft/_forever_/Interface/AddOns/OpenMap/Media/Textures/Forever/MapDungeonDrawn")

ADDON_OUT = REPO_ROOT / "sfui_dungeon_maps"
MEDIA_OUT = ADDON_OUT / "media"
PATCH_OUT = MEDIA_OUT / "patches"
DATA_OUT = ADDON_OUT / "data" / "dungeon_maps_camelot.lua"

CUSTOM_MAP_NAMES = [
    "AlcazPrisonMap",
    "AlcazPrisonMap2",
    "BlackmawHoldBurrowMap",
    "BlackmawHoldEldersMap",
    "BlackmawHoldFallenGroveMap",
    "BlackmawHoldFesteringGrottoMap",
    "BlackmawHoldForbiddenMagicMap",
    "BlackmawHoldGroveMap",
    "DalaranCityMap",
    "DalaranUnderbellyMap",
    "DrownedCityAtalByzalMap",
    "DrownedCityMap",
    "ExcavationSiteMap",
    "HallOfThanesMap",
    "KroldokMap",
    "RuinsOfLordaeronMap",
    "ShapersTerraceMap",
    "SunkenTempleMap",
    "UpperBlackrockSpireMap",
    "WailingCavernsFull",
    "ZulFarrakMap",
]

DXT5_MAPS = {"DalaranCityMap", "DalaranUnderbellyMap"}

FDJ_TO_SFUI_DUNGEON = {
    "Blackfathom Deeps": "blackfathom_deeps",
    "Gnomeregan": "gnomeregan",
    "Ragefire Chasm": "ragefire_chasm",
    "Razorfen Kraul": "razorfen_kraul",
    "Scarlet Monastery: Graveyard": "scarlet_monastery_graveyard",
    "Shadowfang Keep": "shadowfang_keep",
    "The Deadmines": "the_deadmines",
    "The Stockade": "the_stockade",
}


def encode_blp2(out_path: Path, im: Image.Image, fmt: str) -> None:
    """Encode a power-of-two PIL Image into WoW BLP2 (DXT1 or DXT5 with full mipmaps)."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    w, h = im.size
    assert w > 0 and (w & (w - 1)) == 0, f"non-POT width {w} for {out_path.name}"
    assert h > 0 and (h & (h - 1)) == 0, f"non-POT height {h} for {out_path.name}"

    if fmt == "dxt5":
        im_conv = im.convert("RGBA")
        alpha_depth, alpha_enc, block_bytes = 8, 7, 16
    elif fmt == "dxt1":
        im_conv = im.convert("RGB")
        alpha_depth, alpha_enc, block_bytes = 0, 0, 8
    else:
        raise ValueError(f"unsupported fmt: {fmt}")

    mip_dims = []
    cw, ch = w, h
    while True:
        mip_dims.append((cw, ch))
        if cw == 1 and ch == 1:
            break
        cw = max(1, cw // 2)
        ch = max(1, ch // 2)
    extra_mips = max(0, len(mip_dims) - 1)

    import io
    png_buf = io.BytesIO()
    im_conv.save(png_buf, format="PNG", compress_level=1)

    proc = subprocess.run(
        [
            "/usr/bin/magick",
            "-limit", "thread", "2",
            "-limit", "memory", "256MiB",
            "-limit", "map", "256MiB",
            "png:-",
            "-define", f"dds:compression={fmt}",
            "-define", f"dds:mipmaps={extra_mips}",
            "dds:-",
        ],
        input=png_buf.getvalue(),
        capture_output=True,
        check=True,
    )
    dds = proc.stdout
    if len(dds) < 128 or dds[:4] != b"DDS ":
        raise RuntimeError(f"Unexpected DDS header from magick for {out_path.name}")

    cursor = 128
    header_size = 148 + 1024
    mip_offsets = [0] * 16
    mip_sizes = [0] * 16
    mip_blobs = []
    cur_out = header_size

    for idx, (mw, mh) in enumerate(mip_dims):
        if idx >= 16:
            break
        bw = max(1, (mw + 3) // 4)
        bh = max(1, (mh + 3) // 4)
        sz = bw * bh * block_bytes
        if cursor + sz > len(dds):
            raise RuntimeError(
                f"DDS mip {idx} ({mw}x{mh}) truncated for {out_path.name}: need {cursor + sz}, got {len(dds)}"
            )
        mip_offsets[idx] = cur_out
        mip_sizes[idx] = sz
        mip_blobs.append(dds[cursor : cursor + sz])
        cursor += sz
        cur_out += sz

    header = struct.pack(
        "<4sIBBBBII",
        b"BLP2",
        1,
        2,
        alpha_depth,
        alpha_enc,
        1 if extra_mips > 0 else 0,
        w,
        h,
    )
    table = struct.pack("<16I16I", *(mip_offsets + mip_sizes))
    out_path.write_bytes(header + table + bytes(1024) + b"".join(mip_blobs))


def validate_blp2(path: Path, expected_w: int, expected_h: int) -> None:
    data = path.read_bytes()
    assert len(data) >= 1172, f"file too small: {path}"
    magic, ver, enc, _adepth, _aenc, _mips, w, h = struct.unpack("<4sIBBBBII", data[:20])
    assert magic == b"BLP2" and ver == 1 and enc == 2, f"bad header in {path}: {(magic, ver, enc)}"
    assert (w, h) == (expected_w, expected_h), f"dim mismatch in {path}: {(w, h)} != {(expected_w, expected_h)}"
    offs = struct.unpack("<16I", data[20:84])
    sizes = struct.unpack("<16I", data[84:148])
    total_mips = sum(s for s in sizes if s > 0)
    assert len(data) == 1172 + total_mips, f"byte length mismatch in {path}: {len(data)} != {1172 + total_mips}"
    for off, sz in zip(offs, sizes):
        if sz > 0:
            assert off + sz <= len(data), f"mip out of bounds in {path}"


def parse_fdj_patches():
    """Parse exact per-dungeon, per-floor patches from FDJ Core/Journal.lua."""
    src = FDJ_JOURNAL.read_text(encoding="utf-8")
    start = src.index("FDJ.DUNGEON_MAPS = {")
    end = src.index("FDJ.RenderMapLinks =", start)
    block = src[start:end]

    result = {}
    used_names = set()
    # Split per top-level dungeon key inside FDJ.DUNGEON_MAPS
    entries = list(re.finditer(r'^\s{4}\["([^"]+)"\]\s*=\s*\{', block, re.M))
    for idx, m in enumerate(entries):
        dname = m.group(1)
        seg_start = m.end()
        seg_end = entries[idx + 1].start() if idx + 1 < len(entries) else len(block)
        seg = block[seg_start:seg_end]
        if "patches =" not in seg:
            continue
        assert dname in FDJ_TO_SFUI_DUNGEON, f"unmapped patched dungeon in FDJ: {dname}"
        did = FDJ_TO_SFUI_DUNGEON[dname]

        fl_m = re.search(r'\bfloors\s*=\s*\{(.*?)\n\s{8}\},', seg, re.S)
        assert fl_m, f"could not isolate floors table for {dname}"
        fl_body = fl_m.group(1)
        # Each floor starts with `{ uiMapID = ...`
        floor_chunks = re.findall(r'\{\s*uiMapID\s*=.*?(?=\n\s*\{\s*uiMapID\s*=|\Z)', fl_body, re.S)
        assert floor_chunks, f"no floor chunks matched for {dname}"

        floor_patches = {}
        patch_item_re = re.compile(
            r'\{\s*tex\s*=\s*"[^"]*MapPatches\\\\([^"]+)"\s*,'
            r'\s*x0\s*=\s*([0-9.]+)\s*,\s*y0\s*=\s*([0-9.]+)\s*,'
            r'\s*x1\s*=\s*([0-9.]+)\s*,\s*y1\s*=\s*([0-9.]+)'
            r'(?:\s*,\s*alpha\s*=\s*([0-9.]+))?\s*\}'
        )
        for fi, fc in enumerate(floor_chunks, 1):
            plist = []
            for pm in patch_item_re.finditer(fc):
                pname, x0, y0, x1, y1, alpha = pm.groups()
                used_names.add(pname)
                plist.append((pname, float(x0), float(y0), float(x1), float(y1), float(alpha) if alpha else None))
            if plist:
                floor_patches[fi] = plist
        if floor_patches:
            result[did] = floor_patches
    return result, used_names


def main():
    total_src = 0
    total_dst = 0

    # 1. Convert 21 existing custom map TGAs
    for name in CUSTOM_MAP_NAMES:
        src = SRC_MEDIA / f"{name}.tga"
        assert src.exists(), f"missing source TGA: {src}"
        dst = MEDIA_OUT / f"{name}.blp"
        fmt = "dxt5" if name in DXT5_MAPS else "dxt1"
        with Image.open(src) as im:
            w, h = im.size
            encode_blp2(dst, im, fmt)
        validate_blp2(dst, w, h)
        total_src += src.stat().st_size
        total_dst += dst.stat().st_size
        print(f"map   {name:32s} {fmt.upper():4s} {src.stat().st_size:9,d} -> {dst.stat().st_size:7,d}")

    # 2. Stitch OpenMap prismatic-talus_1..12.tga -> PrismaticTalusMap.blp
    canvas = Image.new("RGB", (1024, 1024), (0, 0, 0))
    tile_src_bytes = 0
    for i in range(1, 13):
        tp = OM_DRAWN / f"prismatic-talus_{i}.tga"
        assert tp.exists(), f"missing tile {tp}"
        tile_src_bytes += tp.stat().st_size
        col, row = (i - 1) % 4, (i - 1) // 4
        with Image.open(tp) as tim:
            canvas.paste(tim.convert("RGB"), (col * 256, row * 256))
    pt_dst = MEDIA_OUT / "PrismaticTalusMap.blp"
    encode_blp2(pt_dst, canvas, "dxt1")
    validate_blp2(pt_dst, 1024, 1024)
    total_src += tile_src_bytes
    total_dst += pt_dst.stat().st_size
    print(f"map   {'PrismaticTalusMap':32s} DXT1 {tile_src_bytes:9,d} -> {pt_dst.stat().st_size:7,d}")

    # 3. Parse and encode the 38 used FDJ MapPatches
    patches_by_dungeon, used_names = parse_fdj_patches()
    assert len(used_names) == 38, f"expected 38 used patches, got {len(used_names)}"

    patch_src_bytes = 0
    patch_dst_bytes = 0
    for pname in sorted(used_names):
        src = FDJ_PATCHES / f"{pname}.tga"
        assert src.exists(), f"missing FDJ patch TGA: {src}"
        dst = PATCH_OUT / f"{pname}.blp"
        with Image.open(src) as im:
            w, h = im.size
            use_dxt5 = ("A" in im.mode) and (im.getchannel("A").getextrema()[0] < 255)
            fmt = "dxt5" if use_dxt5 else "dxt1"
            encode_blp2(dst, im, fmt)
        validate_blp2(dst, w, h)
        patch_src_bytes += src.stat().st_size
        patch_dst_bytes += dst.stat().st_size
    print(f"patch {len(used_names)} files                        {patch_src_bytes:9,d} -> {patch_dst_bytes:7,d}")

    # 4. Generate sfui_dungeon_maps/data/dungeon_maps_camelot.lua
    DATA_OUT.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "-- Auto-generated by scripts/build_dungeon_maps.py",
        "sfui = sfui or {}",
        "",
        "sfui.dungeon_maps_pack = {",
        '    texBase = "Interface\\\\AddOns\\\\sfui_dungeon_maps\\\\media\\\\",',
        '    patchBase = "Interface\\\\AddOns\\\\sfui_dungeon_maps\\\\media\\\\patches\\\\",',
        "    patches = {",
    ]
    for did in sorted(patches_by_dungeon):
        lines.append(f"        {did} = {{")
        for fidx in sorted(patches_by_dungeon[did]):
            items = []
            for pname, x0, y0, x1, y1, alpha in patches_by_dungeon[did][fidx]:
                if alpha is not None:
                    a_str = f"{alpha:g}"
                    items.append(f'{{ "{pname}", {x0:.4f}, {y0:.4f}, {x1:.4f}, {y1:.4f}, {a_str} }}')
                else:
                    items.append(f'{{ "{pname}", {x0:.4f}, {y0:.4f}, {x1:.4f}, {y1:.4f} }}')
            lines.append(f"            [{fidx}] = {{ {', '.join(items)} }},")
        lines.append("        },")
    lines.append("    },")
    lines.append("}")
    DATA_OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"\nTOTAL encoded maps+patches: {total_src + patch_src_bytes:,} -> {total_dst + patch_dst_bytes:,} bytes")
    print(f"Generated {DATA_OUT}")


if __name__ == "__main__":
    main()
