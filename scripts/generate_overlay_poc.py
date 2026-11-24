#!/usr/bin/env python3
"""Offline CASC -> ARPG architectural contour/hatch tile & QuestieDB manifest generator.

Generates crisp, vector-anti-aliased minimap overlay tiles from local CASC 3D/terrain data:
  - Scarlet Monastery (instanceID 189: Graveyard, Library, Armory, Cathedral via WDT 788662)
  - Undercity (uiMapID 1458, stitched WMO minimap + 3D WMO obstacle geometry)
  - Deathknell & Tirisfal Glades outdoor terrain/buildings (continent 0 tiles tx=25..34, ty=24..30)
  - Deathknell & Tirisfal 3D WMO caves/crypts + SM Grand Vestibule (uiMapID 19, WMO 107218)
Plus:
  - Radial feather mask (media/overlay_poc/radial_mask.tga)
  - Pre-indexed QuestieDB entities & Scarlet Monastery wing/portal/boss pins (data/overlay_poc_camelot.lua)
  - Visual preview PNGs in the session artifact directory.
"""

from __future__ import annotations

import argparse
import base64
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
import gc
import glob
import io
import math
import os
import re
import resource
import struct
import subprocess
import threading
import time
import zlib
from collections import defaultdict
from pathlib import Path

for _env_k in (
    "OMP_NUM_THREADS",
    "OPENBLAS_NUM_THREADS",
    "MKL_NUM_THREADS",
    "NUMEXPR_NUM_THREADS",
    "VECLIB_MAXIMUM_THREADS",
    "MAGICK_THREAD_LIMIT",
):
    os.environ.setdefault(_env_k, "1")

import cv2
import numpy as np
from PIL import Image, ImageDraw

cv2.setNumThreads(1)

WOW_ROOT = Path("/home/james/Games/World of Warcraft")
ADDONS_DIR = WOW_ROOT / "_forever_/Interface/AddOns"
SFUI_ROOT = Path("/home/james/projects/sfui")
OVERLAY_UI_MEDIA = SFUI_ROOT / "media/overlay"
MAPS_ADDON_ROOT = SFUI_ROOT / "sfui_overlay_maps"
MEDIA_OUT = MAPS_ADDON_ROOT / "media"
DATA_OUT = MAPS_ADDON_ROOT / "data/overlay_maps_camelot.lua"
MAGICK_BIN = "/usr/bin/magick"
ARTIFACT_DIR = Path(
    "/home/james/.gemini/antigravity/brain/6981c98f-5052-43cd-a54e-b691a2391622"
)

TILE_YARDS = 1600.0 / 3.0
TILE_PX = 512
SS_FACTOR = 2
CHUNK_CORE_TILES = 2
OUTDOOR_TX_RANGE = range(25, 35)  # wy: +3733.33 West -> -1600.00 East
OUTDOOR_TY_RANGE = range(24, 31)  # wx: +4266.67 North -> +533.33 South
AZEROTH_WDT_FID = 775971
KALIMDOR_WDT_FID = 782779
SM_WDT_FID = 788662
SM_STEP_YARDS = 96.0
KNOWN_ROAD_TEX_FIDS = {188964, 189000, 188951, 186798, 189016}
ROAD_TEX_FIDS = set(KNOWN_ROAD_TEX_FIDS)

CONTINENTS: dict[int, tuple[str, str, int]] = {
    0: ("ek", "eastern kingdoms", AZEROTH_WDT_FID),
    1: ("kal", "kalimdor", KALIMDOR_WDT_FID),
}

# Subterranean capital cities mapped via OpenMap CaveMinimap + 3D WMO geometry
SUBTERRANEAN_CITIES: dict[int, dict[str, object]] = {
    1458: {
        "name": "undercity",
        "cont": 0,
        "wx_max": 1984.0,
        "wx_min": 1216.0,
        "wy_max": 752.0,
        "wy_min": -16.0,
        "wmo_fid": 7675285,
        "tx_range": (29, 32),
        "ty_range": (27, 30),
        "max_walk_z": 46.0,
        "detect_canals": True,
    },
    1455: {
        "name": "ironforge",
        "cont": 0,
        "wx_max": -4480.0,
        "wx_min": -5248.0,
        "wy_max": -768.0,
        "wy_min": -1536.0,
        "wmo_fid": 7801267,
        "tx_range": (32, 36),
        "ty_range": (39, 43),
        "max_walk_z": None,
        "detect_canals": False,
    },
}

# Scarlet Monastery (instanceID 189) WDT 788662 wing WMOs
SM_WINGS = {
    7958652: ("graveyard", 302, "scarlet monastery: graveyard", 30.5),
    7958653: ("library", 303, "scarlet monastery: library", None),
    7958654: ("armory", 304, "scarlet monastery: armory", None),
    7958650: ("cathedral", 305, "scarlet monastery: cathedral", 44.0),
}


class LocalCASC:
    """Pure-Python reader for local Blizzard CASC storage (wowf build)."""

    def __init__(self, wow_root: Path, product: str = "wowf") -> None:
        self.data_dir = wow_root / "Data/data"
        self.config_dir = wow_root / "Data/config"
        build_key = self._read_build_key(wow_root / ".build.info", product)
        cfg = self._read_config(build_key)
        self.root_ckey = bytes.fromhex(cfg["root"].split()[0])
        self.encoding_ekey = bytes.fromhex(cfg["encoding"].split()[-1])
        self.index_map = self._load_indices()
        self._load_encoding()
        self.fid_to_ckey = self._load_root()
        self._wmo_cache: dict[tuple[int, bool], tuple[object, ...]] = {}
        self._wmo_lock = threading.Lock()

    @staticmethod
    def _read_build_key(build_info_path: Path, product: str) -> str:
        lines = build_info_path.read_text(encoding="utf-8").splitlines()
        headers = [h.split("!")[0] for h in lines[0].split("|")]
        p_idx = headers.index("Product")
        b_idx = headers.index("Build Key")
        for line in lines[1:]:
            if not line.strip():
                continue
            cols = line.split("|")
            if cols[p_idx] == product:
                return cols[b_idx]
        raise RuntimeError(f"Product '{product}' not found in {build_info_path}")

    def _read_config(self, build_key: str) -> dict[str, str]:
        cfg_path = self.config_dir / build_key[:2] / build_key[2:4] / build_key
        out: dict[str, str] = {}
        for line in cfg_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
        return out

    def _load_indices(self) -> dict[bytes, tuple[int, int, int]]:
        idx_files: dict[int, tuple[int, Path]] = {}
        for p_str in sorted(glob.glob(str(self.data_dir / "*.idx"))):
            p = Path(p_str)
            fn = p.name
            bucket = int(fn[:2], 16)
            ver = int(fn[2:10], 16)
            if bucket not in idx_files or ver > idx_files[bucket][0]:
                idx_files[bucket] = (ver, p)
        index_map: dict[bytes, tuple[int, int, int]] = {}
        for _, p in idx_files.values():
            raw = p.read_bytes()
            (
                hdr_size,
                _hdr_hash,
                _fmt_ver,
                _bucket_i,
                _extra_b,
                span_sz_b,
                span_offs_b,
                key_b,
                seg_bits,
            ) = struct.unpack_from("<IIHBBBBBB", raw, 0)
            entries_ofs = (8 + hdr_size + 15) & ~15
            rec_sz, _ = struct.unpack_from("<II", raw, entries_ofs)
            pos = entries_ofs + 8
            end = pos + rec_sz
            elen = key_b + span_offs_b + span_sz_b
            seg_mask = (1 << seg_bits) - 1
            while pos + elen <= end:
                ekey = raw[pos : pos + key_b]
                off_raw = int.from_bytes(
                    raw[pos + key_b : pos + key_b + span_offs_b], "big"
                )
                sz = int.from_bytes(
                    raw[pos + key_b + span_offs_b : pos + elen], "little"
                )
                index_map[ekey] = (off_raw >> seg_bits, off_raw & seg_mask, sz)
                pos += elen
        return index_map

    def read_blte(self, ekey: bytes) -> bytes:
        arch, ofs, sz = self.index_map[ekey[:9]]
        with open(self.data_dir / f"data.{arch:03d}", "rb") as f:
            f.seek(ofs + 30)
            blob = f.read(sz - 30)
        if blob[:4] != b"BLTE":
            raise RuntimeError(f"Invalid BLTE header: {blob[:8]!r}")
        hdr_sz = struct.unpack_from(">I", blob, 4)[0]
        if hdr_sz == 0:
            chunks = [(len(blob) - 8, 8)]
        else:
            cnt = int.from_bytes(blob[9:12], "big")
            chunks = []
            cpos = 12
            doff = hdr_sz
            for _ in range(cnt):
                csz, _ = struct.unpack_from(">II", blob, cpos)
                chunks.append((csz, doff))
                doff += csz
                cpos += 24
        out = bytearray()
        for csz, doff in chunks:
            mode = chr(blob[doff])
            payload = blob[doff + 1 : doff + csz]
            if mode == "N":
                out.extend(payload)
            elif mode == "Z":
                out.extend(zlib.decompress(payload))
            else:
                raise RuntimeError(f"Unsupported BLTE chunk mode {mode!r}")
        return bytes(out)

    def _load_encoding(self) -> None:
        enc = self.read_blte(self.encoding_ekey)
        if enc[:2] != b"EN":
            raise RuntimeError("Invalid encoding header")
        (
            _ver,
            _h_ckey,
            _h_ekey,
            cpage_kb,
            _epage_kb,
            cpage_cnt,
            _epage_cnt,
            _unk,
            spec_sz,
        ) = struct.unpack_from(">BBBHHIIBI", enc, 2)
        self._enc = enc
        self._c_idx_ofs = 22 + spec_sz
        self._c_pages_ofs = self._c_idx_ofs + cpage_cnt * 32
        self._cpage_cnt = cpage_cnt
        self._cpage_sz = cpage_kb * 1024

    def ckey_to_ekey(self, ckey: bytes) -> bytes | None:
        lo, hi, page = 0, self._cpage_cnt - 1, 0
        enc = self._enc
        idx_ofs = self._c_idx_ofs
        while lo <= hi:
            mid = (lo + hi) // 2
            first_key = enc[idx_ofs + mid * 32 : idx_ofs + mid * 32 + 16]
            if first_key <= ckey:
                page = mid
                lo = mid + 1
            else:
                hi = mid - 1
        p = self._c_pages_ofs + page * self._cpage_sz
        pend = p + self._cpage_sz
        while p + 22 <= pend:
            kcnt = enc[p]
            if kcnt == 0:
                break
            if enc[p + 6 : p + 22] == ckey:
                return enc[p + 22 : p + 38]
            p += 22 + kcnt * 16
        return None

    def _load_root(self) -> dict[int, bytes]:
        root_ekey = self.ckey_to_ekey(self.root_ckey)
        if not root_ekey:
            raise RuntimeError("Failed to resolve root CKey")
        root_raw = self.read_blte(root_ekey)
        if root_raw[:4] != b"TSFM":
            raise RuntimeError(f"Unsupported root magic: {root_raw[:4]!r}")
        _magic, hdr_sz, _ver, total_files, named_files, _pad = struct.unpack_from(
            "<IIIIII", root_raw, 0
        )
        allow_non_named = total_files != named_files
        pos = hdr_sz
        fid_to_ckey: dict[int, bytes] = {}
        while pos < len(root_raw):
            num_rec, loc_mask, _f1, f2, _f3 = struct.unpack_from(
                "<IIIIB", root_raw, pos
            )
            pos += 17
            deltas = struct.unpack_from(f"<{num_rec}i", root_raw, pos)
            pos += 4 * num_rec
            ckeys_raw = root_raw[pos : pos + 16 * num_rec]
            pos += 16 * num_rec
            no_namehash = allow_non_named and ((f2 & 0x10000000) != 0)
            if not no_namehash:
                pos += 8 * num_rec
            fid = -1
            is_en = (loc_mask & 0x2) != 0
            for i, d in enumerate(deltas):
                fid += 1 + d
                if is_en or fid not in fid_to_ckey:
                    fid_to_ckey[fid] = ckeys_raw[i * 16 : (i + 1) * 16]
        return fid_to_ckey

    def read_fid(self, fid: int) -> bytes:
        ckey = self.fid_to_ckey[fid]
        ekey = self.ckey_to_ekey(ckey)
        if not ekey:
            raise KeyError(f"No EKey for FID {fid}")
        return self.read_blte(ekey)

    def read_blp_rgba(self, fid: int) -> Image.Image:
        return Image.open(io.BytesIO(self.read_fid(fid))).convert("RGBA")


def save_tga_rle(path: Path, rgba: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im = Image.fromarray(rgba, mode="RGBA")
    im.save(path, format="TGA", compression="tga_rle")


def save_png(path: Path, rgba: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im = Image.fromarray(rgba, mode="RGBA")
    im.save(path, format="PNG", compress_level=9)


def save_blp2_dxt5(path: Path, rgba: np.ndarray, magick_threads: int = 1) -> None:
    """Encode RGBA tile into WoW native BLP2 (DXT5/BC3 with full mipmaps) via ImageMagick."""
    path.parent.mkdir(parents=True, exist_ok=True)
    h, w = rgba.shape[:2]
    mip_dims: list[tuple[int, int]] = []
    cw, ch = w, h
    while True:
        mip_dims.append((cw, ch))
        if cw == 1 and ch == 1:
            break
        cw = max(1, cw // 2)
        ch = max(1, ch // 2)
    extra_mips = max(0, len(mip_dims) - 1)

    png_buf = io.BytesIO()
    Image.fromarray(rgba, mode="RGBA").save(png_buf, format="PNG", compress_level=1)
    proc = subprocess.run(
        [
            MAGICK_BIN,
            "-limit",
            "thread",
            str(max(1, int(magick_threads))),
            "-limit",
            "memory",
            "256MiB",
            "-limit",
            "map",
            "256MiB",
            "png:-",
            "-define",
            "dds:compression=dxt5",
            "-define",
            f"dds:mipmaps={extra_mips}",
            "dds:-",
        ],
        input=png_buf.getvalue(),
        capture_output=True,
        check=True,
    )
    dds = proc.stdout
    if len(dds) < 128 or dds[:4] != b"DDS ":
        raise RuntimeError(f"Unexpected DDS header from magick for {path.name}")

    cursor = 128
    header_size = 148 + 1024
    mip_offsets = [0] * 16
    mip_sizes = [0] * 16
    mip_blobs: list[bytes] = []
    cur_out = header_size

    for idx, (mw, mh) in enumerate(mip_dims):
        if idx >= 16:
            break
        blocks_w = max(1, (mw + 3) // 4)
        blocks_h = max(1, (mh + 3) // 4)
        sz = blocks_w * blocks_h * 16
        if cursor + sz > len(dds):
            raise RuntimeError(
                f"DDS mip {idx} ({mw}x{mh}) truncated for {path.name}: need {cursor + sz}, got {len(dds)}"
            )
        mip_offsets[idx] = cur_out
        mip_sizes[idx] = sz
        mip_blobs.append(dds[cursor : cursor + sz])
        cursor += sz
        cur_out += sz

    header = struct.pack(
        "<4sIBBBBII",
        b"BLP2",
        1,   # BLP2 version / compression type
        2,   # encoding = DXT
        8,   # alphaDepth = 8-bit
        7,   # alphaEncoding = DXT5
        1 if extra_mips > 0 else 0,
        w,
        h,
    )
    table = struct.pack("<16I16I", *(mip_offsets + mip_sizes))
    palette = bytes(1024)
    path.write_bytes(header + table + palette + b"".join(mip_blobs))


def generate_radial_mask(out_path: Path, size: int = 256) -> None:
    """Radial fade with outer soft edge AND soft inner player clear zone around (0,0)."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) * 0.5
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (size * 0.5)

    t_out = np.clip((r - 0.60) / (0.98 - 0.60), 0.0, 1.0)
    outer = 0.5 * (1.0 + np.cos(math.pi * t_out))

    t_in = np.clip((r - 0.035) / (0.095 - 0.035), 0.0, 1.0)
    inner = 0.38 + 0.62 * 0.5 * (1.0 - np.cos(math.pi * t_in))

    alpha = np.round(outer * inner * 255.0).astype(np.uint8)
    rgba = np.empty((size, size, 4), dtype=np.uint8)
    rgba[:, :, :3] = 255
    rgba[:, :, 3] = alpha
    save_tga_rle(out_path, rgba)


def generate_chevron_texture(out_path: Path, size: int = 64) -> None:
    """Upward-pointing anti-aliased white directional chevron (recolorable via SetVertexColor)."""
    ss = 4
    hi = size * ss
    canvas = np.zeros((hi, hi, 4), dtype=np.float32)
    cx = hi * 0.5
    pts = np.array(
        [
            [cx, hi * 0.14],
            [hi * 0.84, hi * 0.78],
            [cx, hi * 0.60],
            [hi * 0.16, hi * 0.78],
        ],
        dtype=np.int32,
    )
    halo = np.zeros((hi, hi), dtype=np.float32)
    cv2.polylines(halo, [pts], isClosed=True, color=1.0, thickness=ss * 5, lineType=cv2.LINE_AA)
    halo = cv2.GaussianBlur(halo, (0, 0), sigmaX=ss * 1.1)
    canvas[:, :, :3] = 0.08 * 255.0
    canvas[:, :, 3] = np.clip(halo * 0.85, 0.0, 1.0) * 255.0

    fill_m = np.zeros((hi, hi), dtype=np.float32)
    cv2.fillPoly(fill_m, [pts], 1.0, lineType=cv2.LINE_AA)
    over_a = np.clip(fill_m, 0.0, 1.0)
    # premultiplied white over halo -> unpremultiply
    out_a = over_a + (canvas[:, :, 3] / 255.0) * (1.0 - over_a)
    for ch in range(3):
        pre = 255.0 * over_a + (canvas[:, :, ch] * (canvas[:, :, 3] / 255.0)) * (1.0 - over_a)
        canvas[:, :, ch] = np.where(out_a > 1e-4, np.clip(pre / np.maximum(out_a, 1e-4), 0.0, 255.0), 0.0)
    canvas[:, :, 3] = np.clip(out_a * 255.0, 0.0, 255.0)

    im = Image.fromarray(np.round(canvas).astype(np.uint8), mode="RGBA").resize(
        (size, size), resample=Image.Resampling.LANCZOS
    )
    save_tga_rle(out_path, np.array(im))


def parse_adt_terrain(
    adt_bytes: bytes,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Extract MCNR nz (129x129), MCVT height (129x129), and MH2O water mask (128x128) for one ADT tile."""
    nz_grid = np.ones((129, 129), dtype=np.float32)
    h_grid = np.zeros((129, 129), dtype=np.float32)
    water_grid = np.zeros((128, 128), dtype=np.uint8)
    mh2o_base = None

    pos = 0
    while pos + 8 <= len(adt_bytes):
        tag = adt_bytes[pos : pos + 4][::-1]
        csz = struct.unpack_from("<I", adt_bytes, pos + 4)[0]
        if tag == b"MCNK":
            hdr = adt_bytes[pos + 8 : pos + 8 + 128]
            flags, ix, iy = struct.unpack_from("<III", hdr, 0)
            _, _, base_z = struct.unpack_from("<3f", hdr, 104)
            if flags & 0x3C:
                water_grid[iy * 8 : (iy + 1) * 8, ix * 8 : (ix + 1) * 8] = 1
            sp = pos + 8 + 128
            end = pos + 8 + csz
            got_n, got_v = False, False
            while sp + 8 <= end:
                stag = adt_bytes[sp : sp + 4][::-1]
                ssz = struct.unpack_from("<I", adt_bytes, sp + 4)[0]
                if stag == b"MCNR":
                    norms = struct.unpack_from("<435b", adt_bytes, sp + 8)
                    for r in range(9):
                        for c in range(9):
                            idx = r * 17 + c
                            nz = norms[idx * 3 + 2]
                            nz_grid[iy * 8 + r, ix * 8 + c] = max(
                                -1.0, min(1.0, nz / 127.0)
                            )
                    got_n = True
                elif stag == b"MCVT":
                    verts = struct.unpack_from("<145f", adt_bytes, sp + 8)
                    for r in range(9):
                        for c in range(9):
                            idx = r * 17 + c
                            h_grid[iy * 8 + r, ix * 8 + c] = base_z + verts[idx]
                    got_v = True
                sp += 8 + ssz
                if stag == b"MCNR":
                    sp += 13
                if got_n and got_v:
                    break
        elif tag == b"MH2O":
            mh2o_base = pos + 8
        pos += 8 + csz

    if mh2o_base is not None:
        for ci in range(256):
            ofs_inst, lcnt, _ = struct.unpack_from("<III", adt_bytes, mh2o_base + ci * 12)
            if lcnt <= 0 or ofs_inst == 0:
                continue
            iy = ci // 16
            ix = ci % 16
            for li in range(lcnt):
                (
                    _ltype,
                    _lvf,
                    _minh,
                    _maxh,
                    x_ofs,
                    y_ofs,
                    w,
                    h,
                    ofs_exist,
                    _ofs_vtx,
                ) = struct.unpack_from(
                    "<HHffBBBBII", adt_bytes, mh2o_base + ofs_inst + li * 24
                )
                if ofs_exist == 0:
                    water_grid[
                        iy * 8 + y_ofs : iy * 8 + y_ofs + h,
                        ix * 8 + x_ofs : ix * 8 + x_ofs + w,
                    ] = 1
                else:
                    nbytes = (w * h + 7) // 8
                    eb = adt_bytes[mh2o_base + ofs_exist : mh2o_base + ofs_exist + nbytes]
                    for rr in range(h):
                        for cc in range(w):
                            bit_i = rr * w + cc
                            if eb[bit_i // 8] & (1 << (bit_i % 8)):
                                water_grid[iy * 8 + y_ofs + rr, ix * 8 + x_ofs + cc] = 1
    return nz_grid, h_grid, water_grid


def _decode_mcal_layer(mcal: bytes, ofs: int, flags: int) -> np.ndarray:
    if flags & 0x200:
        out = bytearray()
        p = ofs
        while len(out) < 4096 and p < len(mcal):
            c = mcal[p]
            p += 1
            cnt = c & 0x7F
            if c & 0x80:
                v = mcal[p]
                p += 1
                out.extend([v] * cnt)
            else:
                out.extend(mcal[p : p + cnt])
                p += cnt
        return np.frombuffer(bytes(out[:4096]), dtype=np.uint8).reshape(64, 64).astype(np.float32) / 255.0
    return np.frombuffer(mcal, dtype=np.uint8, count=4096, offset=ofs).reshape(64, 64).astype(np.float32) / 255.0


def parse_tex0_roads(tex0_bytes: bytes, road_fids: set[int]) -> np.ndarray:
    """Extract blended weight [0..1] of road/cobble textures at 1024x1024 from _tex0.adt."""
    road_grid = np.zeros((1024, 1024), dtype=np.float32)
    mdid: list[int] = []
    tp = 0
    ci = 0
    while tp + 8 <= len(tex0_bytes):
        tt = tex0_bytes[tp : tp + 4][::-1]
        tsz = struct.unpack_from("<I", tex0_bytes, tp + 4)[0]
        if tt == b"MDID":
            mdid = list(struct.unpack_from(f"<{tsz // 4}I", tex0_bytes, tp + 8))
        elif tt == b"MCNK":
            iy, ix = ci // 16, ci % 16
            ci += 1
            sp = tp + 8
            end = sp + tsz
            mcly: list[tuple[int, int, int, int]] = []
            mcal = b""
            while sp + 8 <= end:
                st = tex0_bytes[sp : sp + 4][::-1]
                ssz = struct.unpack_from("<I", tex0_bytes, sp + 4)[0]
                if st == b"MCLY":
                    mcly = [struct.unpack_from("<IIII", tex0_bytes, sp + 8 + k) for k in range(0, ssz, 16)]
                elif st == b"MCAL":
                    mcal = tex0_bytes[sp + 8 : sp + 8 + ssz]
                sp += 8 + ssz
            if mcly and mdid:
                weights = [np.ones((64, 64), dtype=np.float32)]
                for tid, flg, ofs, _ in mcly[1:]:
                    a = _decode_mcal_layer(mcal, ofs, flg) if (flg & 0x100) else np.zeros((64, 64), dtype=np.float32)
                    inv = 1.0 - a
                    for prev_i in range(len(weights)):
                        weights[prev_i] *= inv
                    weights.append(a)
                r_chunk = np.zeros((64, 64), dtype=np.float32)
                for (tid, _, _, _), lw in zip(mcly, weights):
                    if tid < len(mdid) and mdid[tid] in road_fids:
                        r_chunk += lw
                road_grid[iy * 64 : (iy + 1) * 64, ix * 64 : (ix + 1) * 64] = r_chunk
        tp += 8 + tsz
    return road_grid


def remove_small_components(mask: np.ndarray, min_area: int) -> np.ndarray:
    num, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask.astype(np.uint8), connectivity=8
    )
    if num <= 1:
        return mask
    keep = np.zeros(num, dtype=bool)
    for i in range(1, num):
        if stats[i, cv2.CC_STAT_AREA] >= min_area:
            keep[i] = True
    return keep[labels]


def over_premul(
    dst_p: np.ndarray,
    dst_a: np.ndarray,
    src_rgb: tuple[float, float, float] | np.ndarray,
    src_a: np.ndarray,
) -> None:
    """Porter-Duff Source-Over onto float32 premultiplied buffer (RGB in 0..255, A in 0..1)."""
    sa = np.clip(src_a, 0.0, 1.0).astype(np.float32, copy=False)
    inv = 1.0 - sa
    if isinstance(src_rgb, tuple):
        sr, sg, sb = src_rgb
        dst_p[:, :, 0] *= inv
        dst_p[:, :, 0] += sr * sa
        dst_p[:, :, 1] *= inv
        dst_p[:, :, 1] += sg * sa
        dst_p[:, :, 2] *= inv
        dst_p[:, :, 2] += sb * sa
    else:
        dst_p[:, :, 0] *= inv
        dst_p[:, :, 0] += src_rgb[:, :, 0] * sa
        dst_p[:, :, 1] *= inv
        dst_p[:, :, 1] += src_rgb[:, :, 1] * sa
        dst_p[:, :, 2] *= inv
        dst_p[:, :, 2] += src_rgb[:, :, 2] * sa
    dst_a *= inv
    dst_a += sa


def premul_to_rgba(
    dst_p: np.ndarray, dst_a: np.ndarray, downsample: int = 1
) -> np.ndarray:
    if downsample > 1:
        th = max(1, dst_a.shape[0] // downsample)
        tw = max(1, dst_a.shape[1] // downsample)
        dst_p = cv2.resize(dst_p, (tw, th), interpolation=cv2.INTER_AREA)
        dst_a = cv2.resize(dst_a, (tw, th), interpolation=cv2.INTER_AREA)
    H, W = dst_a.shape
    out = np.zeros((H, W, 4), dtype=np.uint8)
    valid = dst_a > 1e-3
    if valid.any():
        inv_a = np.where(valid, 1.0 / np.maximum(dst_a, 1e-4), 0.0)[:, :, None]
        rgb = np.clip(dst_p * inv_a, 0.0, 255.0).round().astype(np.uint8)
        out[:, :, :3] = rgb
        out[:, :, 3] = np.clip(dst_a * 255.0, 0.0, 255.0).round().astype(np.uint8)
        out[~valid] = 0
    return out


def extract_contours(mask: np.ndarray, eps_px: float = 0.70, min_area: float = 12.0) -> list[np.ndarray]:
    """Extract lightly simplified crisp contours for anti-aliased CAD polyline strokes."""
    cnts, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out: list[np.ndarray] = []
    for c in cnts:
        if len(c) < 3 or cv2.contourArea(c) < min_area:
            continue
        if eps_px > 0:
            c = cv2.approxPolyDP(c, eps_px, True)
        if len(c) >= 3:
            out.append(c)
    return out


def composite_aa_contours(
    dst_p: np.ndarray,
    dst_a: np.ndarray,
    contours: list[np.ndarray],
    rgb: tuple[float, float, float],
    peak_alpha: float = 0.92,
    thickness: int = 2,
    halo_thickness: int = 4,
    halo_alpha: float = 0.62,
    halo_blur: float = 0.45,
) -> None:
    """Draw razor-sharp cv2.LINE_AA vector outlines with tight dark contrast backing."""
    if not contours:
        return
    H, W = dst_a.shape
    if halo_alpha > 0 and halo_thickness > 0:
        hmask = np.zeros((H, W), dtype=np.float32)
        cv2.polylines(hmask, contours, True, 1.0, thickness=halo_thickness, lineType=cv2.LINE_AA)
        if halo_blur > 0:
            hmask = cv2.GaussianBlur(hmask, (0, 0), sigmaX=halo_blur, sigmaY=halo_blur)
        over_premul(dst_p, dst_a, (8.0, 10.0, 14.0), hmask * halo_alpha)
        del hmask
    lmask = np.zeros((H, W), dtype=np.float32)
    cv2.polylines(lmask, contours, True, 1.0, thickness=thickness, lineType=cv2.LINE_AA)
    over_premul(dst_p, dst_a, rgb, lmask * peak_alpha)
    del lmask


def composite_diagonal_hatch(
    dst_p: np.ndarray,
    dst_a: np.ndarray,
    dist_into: np.ndarray,
    wash_fade: float = 52.0,
    stripe_fade: float = 66.0,
    wash_alpha: float = 0.40,
    stripe_alpha: float = 0.25,
    angle_deg: float = -66.0,
    period_px: float = 9.0,
    sharpness: float = 3.2,
    max_dist: float | None = None,
) -> None:
    """Fine architectural diagonal hatching over smooth dark shadow falloff."""
    H, W = dist_into.shape
    active = dist_into > 0.0
    if max_dist is not None:
        active = active & (dist_into <= max_dist)
    if not active.any():
        return
    ramp = np.clip(dist_into / 1.2, 0.0, 1.0)
    wash_a = np.zeros((H, W), dtype=np.float32)
    wash_a[active] = np.exp(-dist_into[active] / wash_fade) * ramp[active] * wash_alpha
    if max_dist is not None:
        t_cut = np.clip(1.0 - (dist_into[active] - max_dist * 0.72) / (max_dist * 0.28), 0.0, 1.0)
        wash_a[active] *= t_cut
    over_premul(dst_p, dst_a, (10.0, 12.0, 18.0), wash_a)
    del wash_a

    yy = np.arange(H, dtype=np.float32)[:, None]
    xx = np.arange(W, dtype=np.float32)[None, :]
    ca = math.cos(math.radians(angle_deg)) * (2.0 * math.pi / period_px)
    sa = math.sin(math.radians(angle_deg)) * (2.0 * math.pi / period_px)
    stripe = (0.5 + 0.5 * np.cos(xx * ca + yy * sa)) ** sharpness

    str_a = np.zeros((H, W), dtype=np.float32)
    str_a[active] = np.exp(-dist_into[active] / stripe_fade) * ramp[active] * stripe_alpha
    if max_dist is not None:
        str_a[active] *= np.clip(1.0 - (dist_into[active] - max_dist * 0.72) / (max_dist * 0.28), 0.0, 1.0)
    stripe *= str_a
    del str_a, ramp, active
    over_premul(dst_p, dst_a, (164.0, 170.0, 182.0), stripe)
    del stripe


def slice_triangles_at_z(tp: np.ndarray, z_s: float) -> tuple[np.ndarray, np.ndarray]:
    """Vectorized triangle vs horizontal plane Z=z_s intersection returning (p1, p2) XY segments."""
    dz = tp[:, :, 2] - z_s
    dz = np.where(dz == 0.0, 1e-4, dz)
    pos_cnt = (dz > 0.0).sum(axis=1)
    neg_cnt = (dz < 0.0).sum(axis=1)
    one_pos = pos_cnt == 1
    one_neg = neg_cnt == 1
    hit = one_pos | one_neg
    if not hit.any():
        return np.empty((0, 2), dtype=np.float32), np.empty((0, 2), dtype=np.float32)
    tp_h = tp[hit]
    dz_h = dz[hit]
    op_h = one_pos[hit]
    lone = np.where(op_h, np.argmax(dz_h > 0.0, axis=1), np.argmax(dz_h < 0.0, axis=1))
    rows = np.arange(len(tp_h))
    i0 = lone
    i1 = (lone + 1) % 3
    i2 = (lone + 2) % 3
    d0 = dz_h[rows, i0]
    d1 = dz_h[rows, i1]
    d2 = dz_h[rows, i2]
    t1 = d0 / (d0 - d1)
    t2 = d0 / (d0 - d2)
    p1 = tp_h[rows, i0, :2] + t1[:, None] * (tp_h[rows, i1, :2] - tp_h[rows, i0, :2])
    p2 = tp_h[rows, i0, :2] + t2[:, None] * (tp_h[rows, i2, :2] - tp_h[rows, i0, :2])
    return p1.astype(np.float32), p2.astype(np.float32)


def _load_wmo_local(
    casc: LocalCASC, wfid: int, indoor_only: bool
) -> list[tuple[float, np.ndarray, np.ndarray, np.ndarray, np.ndarray, bool]]:
    """Cache decoded WMO local vertices/triangles per group so shared building models decode once."""
    key = (wfid, indoor_only)
    with casc._wmo_lock:
        cached = casc._wmo_cache.get(key)  # type: ignore[assignment]
    if cached is not None:
        return cached  # type: ignore[return-value]

    groups_out: list[tuple[float, np.ndarray, np.ndarray, np.ndarray, np.ndarray, bool]] = []
    try:
        wmo = casc.read_fid(wfid)
    except Exception:
        with casc._wmo_lock:
            if len(casc._wmo_cache) >= 48:
                casc._wmo_cache.clear()
            casc._wmo_cache[key] = groups_out  # type: ignore[assignment]
        return groups_out

    wp = 0
    mogi: list[tuple[int, float]] = []
    gfids: list[int] = []
    while wp + 8 <= len(wmo):
        wt = wmo[wp : wp + 4][::-1]
        wsz = struct.unpack_from("<I", wmo, wp + 4)[0]
        if wt == b"MOGI":
            for k in range(0, wsz, 32):
                fl, _bx0, _by0, bz0, _bx1, _by1, _bz1, _nofs = struct.unpack_from(
                    "<I6fI", wmo, wp + 8 + k
                )
                mogi.append((fl, bz0))
        elif wt == b"GFID":
            gfids = list(struct.unpack_from(f"<{wsz // 4}I", wmo, wp + 8))
        wp += 8 + wsz

    for (fl, bz0), gf in zip(mogi, gfids):
        if indoor_only and not (fl & 0x2000):
            continue
        if not gf or gf not in casc.fid_to_ckey:
            continue
        try:
            grp = casc.read_fid(gf)
        except Exception:
            continue
        gp = 20 + 68
        v = ix = mp = None
        while gp + 8 <= len(grp):
            gt = grp[gp : gp + 4][::-1]
            gsz = struct.unpack_from("<I", grp, gp + 4)[0]
            if gt == b"MOVT":
                v = np.frombuffer(grp, dtype="<f4", count=gsz // 4, offset=gp + 8).reshape(-1, 3)
            elif gt == b"MOVI":
                ix = (
                    np.frombuffer(grp, dtype="<u2", count=gsz // 2, offset=gp + 8)
                    .reshape(-1, 3)
                    .astype(np.int32)
                )
            elif gt == b"MOPY":
                mp = (
                    np.frombuffer(grp, dtype=np.uint8, count=gsz, offset=gp + 8)
                    .reshape(-1, 2)
                    .astype(np.int32)
                )
            elif gt == b"MPY2":
                mp = (
                    np.frombuffer(grp, dtype="<u2", count=gsz // 2, offset=gp + 8)
                    .reshape(-1, 2)
                    .astype(np.int32)
                )
            gp += 8 + gsz
        if v is None or ix is None or len(ix) == 0:
            continue
        if mp is not None and len(mp) == len(ix):
            g_fl = mp[:, 0]
            g_mat = mp[:, 1]
        else:
            g_fl = np.zeros(len(ix), dtype=np.int32)
            g_mat = np.zeros(len(ix), dtype=np.int32)
        groups_out.append((float(bz0), np.array(v, dtype=np.float32), ix, g_fl, g_mat, bool(fl & 0x2000)))

    with casc._wmo_lock:
        if key not in casc._wmo_cache:
            if len(casc._wmo_cache) >= 48:
                casc._wmo_cache.clear()
            casc._wmo_cache[key] = groups_out  # type: ignore[assignment]
    return groups_out


def extract_wmo_world_tris(
    casc: LocalCASC,
    wfid: int,
    px: float,
    py: float,
    pz: float,
    ry: float,
    scale: float = 1.0,
    *,
    indoor_only: bool = False,
    max_walk_z: float | None = None,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Transform cached WMO group meshes into world coordinates."""
    empty3 = np.empty((0, 3), dtype=np.float32)
    emptyi = np.empty((0, 3), dtype=np.int32)
    empty1f = np.empty((0,), dtype=np.float32)
    empty1i = np.empty((0,), dtype=np.int32)
    empty1b = np.empty((0,), dtype=bool)
    if wfid not in casc.fid_to_ckey:
        return empty3, emptyi, empty1f, empty1i, empty1i, empty1b

    local_groups = _load_wmo_local(casc, wfid, indoor_only)
    if not local_groups:
        return empty3, emptyi, empty1f, empty1i, empty1i, empty1b

    rad = math.radians(ry - 90.0)
    c, s = math.cos(rad), math.sin(rad)

    verts_l, tris_l, nz_l, fl_l, mat_l, in_l = [], [], [], [], [], []
    base = 0
    for bz0, v, ix, g_fl, g_mat, g_in in local_groups:
        if max_walk_z is not None and (py + bz0 * scale) > max_walk_z + 5.0:
            continue
        vs = v * scale
        adt_x = px + (vs[:, 0] * c - vs[:, 1] * s)
        adt_z = pz - (vs[:, 0] * s + vs[:, 1] * c)
        wz = py + vs[:, 2]
        wx = 17066.6666667 - adt_z
        wy = 17066.6666667 - adt_x
        wpts = np.stack([wx, wy, wz], axis=1).astype(np.float32)

        p0, p1, p2 = wpts[ix[:, 0]], wpts[ix[:, 1]], wpts[ix[:, 2]]
        n = np.cross(p1 - p0, p2 - p0)
        nz = n[:, 2] / (np.linalg.norm(n, axis=1) + 1e-8)

        verts_l.append(wpts)
        tris_l.append(ix + base)
        nz_l.append(nz)
        fl_l.append(g_fl)
        mat_l.append(g_mat)
        in_l.append(np.full(len(ix), g_in, dtype=bool))
        base += len(wpts)

    if not verts_l:
        return empty3, emptyi, empty1f, empty1i, empty1i, empty1b

    return (
        np.vstack(verts_l),
        np.vstack(tris_l),
        np.concatenate(nz_l),
        np.concatenate(fl_l),
        np.concatenate(mat_l),
        np.concatenate(in_l),
    )


def build_wmo_floorplan_masks(
    v: np.ndarray,
    tris: np.ndarray,
    nz: np.ndarray,
    mat: np.ndarray,
    is_in: np.ndarray,
    wx_max: float,
    wy_max: float,
    width: int,
    height: int,
    px_per_yard: float,
    *,
    indoor_only: bool = False,
    max_walk_z: float | None = None,
    sky_cap_pad: float = 6.5,
    slice_h: float = 1.25,
) -> tuple[np.ndarray, np.ndarray]:
    """Rasterize walkable WMO floors + slice interior architectural walls/pillars at waist height."""
    rendered = (mat != 0xFF) & (mat != 0xFFFF)
    tmz = v[tris][:, :, 2].mean(axis=1)
    walk_t = rendered & (nz >= 0.50)
    in_walk = walk_t & is_in
    if in_walk.any() and not indoor_only:
        z_cap = float(np.percentile(tmz[in_walk], 95)) + sky_cap_pad
        walk_t = walk_t & (is_in | ((nz >= 0.58) & (tmz <= z_cap)))
    if max_walk_z is not None:
        walk_t = walk_t & (tmz <= max_walk_z)

    walk_mask = np.zeros((height, width), dtype=np.uint8)
    obs_mask = np.zeros((height, width), dtype=np.float32)
    if not walk_t.any():
        return walk_mask > 0, obs_mask

    px_x = (wy_max - v[:, 1]) * px_per_yard
    px_y = (wx_max - v[:, 0]) * px_per_yard

    wt = tris[walk_t]
    polys = np.stack([px_x[wt], px_y[wt]], axis=-1).round().astype(np.int32)
    cv2.fillPoly(walk_mask, list(polys), 1)
    walk_mask = cv2.morphologyEx(walk_mask, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))

    # Quantized local floor height map for accurate multi-story / sloped ramp slicing
    floor_z = np.full((height, width), -9999.0, dtype=np.float32)
    z0_all, z1_all = float(tmz[walk_t].min()), float(tmz[walk_t].max())
    bins = np.arange(z0_all, z1_all + 0.6, 0.5)
    for b_lo in bins:
        sel = walk_t & (tmz >= b_lo) & (tmz < b_lo + 0.5)
        if sel.any():
            bt = tris[sel]
            bm = np.zeros((height, width), dtype=np.uint8)
            cv2.fillPoly(bm, list(np.stack([px_x[bt], px_y[bt]], axis=-1).round().astype(np.int32)), 1)
            floor_z[bm > 0] = b_lo + 0.25

    fz_fill = cv2.dilate(floor_z, np.ones((5, 5), np.uint8))
    miss = (floor_z < -9000.0) & (walk_mask > 0)
    floor_z[miss] = fz_fill[miss]

    # Slice steep walls / pillars / pews / bookcases at Z = local_floor + slice_h
    wall_t = rendered & (np.abs(nz) <= 0.45)
    if wall_t.any():
        w_pts = v[tris[wall_t]]
        w_zmin = w_pts[:, :, 2].min(axis=1)
        w_zmax = w_pts[:, :, 2].max(axis=1)
        for b_lo in bins:
            near_f = (floor_z >= b_lo - 0.1) & (floor_z < b_lo + 0.6)
            if not near_f.any():
                continue
            z_s = float(b_lo + 0.25 + slice_h)
            sel = (w_zmin < z_s) & (w_zmax > z_s)
            if not sel.any():
                continue
            p1, p2 = slice_triangles_at_z(w_pts[sel], z_s)
            if len(p1) == 0:
                continue
            x1 = ((wy_max - p1[:, 1]) * px_per_yard).round().astype(np.int32)
            y1 = ((wx_max - p1[:, 0]) * px_per_yard).round().astype(np.int32)
            x2 = ((wy_max - p2[:, 1]) * px_per_yard).round().astype(np.int32)
            y2 = ((wx_max - p2[:, 0]) * px_per_yard).round().astype(np.int32)
            in_b = (
                (np.maximum(x1, x2) >= 0)
                & (np.minimum(x1, x2) < width)
                & (np.maximum(y1, y2) >= 0)
                & (np.minimum(y1, y2) < height)
                & ((x1 != x2) | (y1 != y2))
            )
            if not in_b.any():
                continue
            wm = np.zeros((height, width), dtype=np.float32)
            for ax, ay, bx, by in zip(x1[in_b], y1[in_b], x2[in_b], y2[in_b]):
                cv2.line(wm, (int(ax), int(ay)), (int(bx), int(by)), 1.0, thickness=1, lineType=cv2.LINE_AA)
            obs_mask = np.maximum(obs_mask, wm * near_f.astype(np.float32))

    walk_clean = remove_small_components(walk_mask > 0, 24)
    return walk_clean, np.clip(obs_mask, 0.0, 1.0)


def render_architectural_map(
    walkable: np.ndarray,
    *,
    interior_lines: np.ndarray | None = None,
    canal_mask: np.ndarray | None = None,
    downsample: int = SS_FACTOR,
    max_hatch_dist: float = 160.0,
    wall_thickness: int = 3,
    halo_thickness: int = 6,
    island_max_area: int = 9000,
) -> np.ndarray:
    """CAD-crisp ARPG dungeon/city renderer matching smooth LINE_AA architectural contours & fine 66deg hatching."""
    H, W = walkable.shape
    dst_p = np.zeros((H, W, 3), dtype=np.float32)
    dst_a = np.zeros((H, W), dtype=np.float32)

    walk_u8 = walkable.astype(np.uint8)

    # 1. Clean, uniform walkable floor fill (ZERO Sobel smudges)
    over_premul(dst_p, dst_a, (22.0, 25.0, 32.0), walk_u8.astype(np.float32) * 0.16)

    # 2. Optional clean slime canals (Undercity only, speckled noise removed)
    if canal_mask is not None and canal_mask.any():
        c_u8 = canal_mask.astype(np.uint8)
        over_premul(dst_p, dst_a, (24.0, 48.0, 30.0), c_u8.astype(np.float32) * 0.22)
        c_cnts = extract_contours(c_u8, eps_px=0.80, min_area=40.0)
        composite_aa_contours(
            dst_p,
            dst_a,
            c_cnts,
            rgb=(126.0, 182.0, 128.0),
            peak_alpha=0.72,
            thickness=wall_thickness,
            halo_thickness=halo_thickness,
            halo_alpha=0.35,
        )

    # 3. Classify freestanding enclosed architectural blocks (pillars, stalls, fountains, altars) vs main outer void
    not_walk = (~walkable).astype(np.uint8)
    num_nw, labels_nw, stats_nw, _ = cv2.connectedComponentsWithStats(not_walk, connectivity=8)
    island_mask = np.zeros((H, W), dtype=np.uint8)
    border_labels = set(np.unique(labels_nw[0, :])) | set(np.unique(labels_nw[-1, :])) | set(np.unique(labels_nw[:, 0])) | set(np.unique(labels_nw[:, -1]))
    for i in range(1, num_nw):
        if i in border_labels:
            continue
        area = int(stats_nw[i, cv2.CC_STAT_AREA])
        if 24 <= area <= island_max_area:
            island_mask[labels_nw == i] = 1

    # Exterior wall rock distance & fine -66deg architectural hatching
    dist_into = cv2.distanceTransform(not_walk, cv2.DIST_L2, 5)
    composite_diagonal_hatch(
        dst_p,
        dst_a,
        dist_into,
        wash_fade=56.0,
        stripe_fade=72.0,
        wash_alpha=0.45,
        stripe_alpha=0.34,
        angle_deg=-66.0,
        period_px=8.6,
        sharpness=3.0,
        max_dist=max_hatch_dist,
    )

    # Highlight freestanding enclosed blocks with warm bronze translucent fill (matching Ironforge reference stalls)
    if island_mask.any():
        over_premul(dst_p, dst_a, (78.0, 58.0, 38.0), island_mask.astype(np.float32) * 0.28)

    # 4. Crisp waist-height interior wall / pew / bookcase / fountain architectural details
    if interior_lines is not None and interior_lines.any():
        eroded = cv2.erode(walk_u8, np.ones((3, 3), np.uint8)) > 0
        lines_in = interior_lines * eroded.astype(np.float32)
        over_premul(dst_p, dst_a, (10.0, 12.0, 16.0), np.clip(lines_in * 0.38, 0.0, 1.0))
        over_premul(dst_p, dst_a, (206.0, 186.0, 148.0), np.clip(lines_in * 0.62, 0.0, 1.0))

    # 5. Razor-sharp LINE_AA vector outlines for outer room silhouettes & freestanding bronze blocks
    outer_only_walk = walkable | (island_mask > 0)
    outer_cnts = extract_contours(outer_only_walk, eps_px=0.68, min_area=18.0)
    composite_aa_contours(
        dst_p,
        dst_a,
        outer_cnts,
        rgb=(224.0, 204.0, 168.0),
        peak_alpha=0.94,
        thickness=wall_thickness,
        halo_thickness=halo_thickness,
        halo_alpha=0.68,
        halo_blur=0.45,
    )
    if island_mask.any():
        isl_cnts = extract_contours(island_mask, eps_px=0.60, min_area=18.0)
        composite_aa_contours(
            dst_p,
            dst_a,
            isl_cnts,
            rgb=(226.0, 180.0, 114.0),
            peak_alpha=0.94,
            thickness=wall_thickness,
            halo_thickness=halo_thickness,
            halo_alpha=0.62,
            halo_blur=0.40,
        )

    return premul_to_rgba(dst_p, dst_a, downsample=downsample)


def rasterize_outdoor_wmos(
    casc: LocalCASC,
    maid_data: bytes,
    tx_list: list[int],
    ty_list: list[int],
    h_mosaic: np.ndarray,
    full_w: int,
    full_h: int,
    tile_px: int,
) -> tuple[np.ndarray, np.ndarray]:
    """Project outdoor 3D WMO footprints AND waist-height interior wall slices onto the full mosaic."""
    out_wx_max = (32 - ty_list[0]) * TILE_YARDS
    out_wy_max = (32 - tx_list[0]) * TILE_YARDS
    h_max_row, h_max_col = h_mosaic.shape[0] - 1, h_mosaic.shape[1] - 1
    px_per_yard = tile_px / TILE_YARDS

    placements: dict[int, tuple[int, float, float, float, float, float]] = {}
    for ty in ty_list:
        for tx in tx_list:
            obj0_fid = struct.unpack_from("<I", maid_data, (ty * 64 + tx) * 32 + 4)[0]
            if not obj0_fid or obj0_fid not in casc.fid_to_ckey:
                continue
            obj0 = casc.read_fid(obj0_fid)
            p = 0
            while p + 8 <= len(obj0):
                t = obj0[p : p + 4][::-1]
                sz = struct.unpack_from("<I", obj0, p + 4)[0]
                if t == b"MODF":
                    for i in range(0, sz, 64):
                        fid, uid, px, py, pz, _rx, ry, _rz, _lx, _ly, _lz, _ux, _uy, _uz, flg, _did, _ns, sc = struct.unpack_from(
                            "<II12fHHHH", obj0, p + 8 + i
                        )
                        if uid not in placements:
                            scale = (sc / 1024.0) if ((flg & 4) and sc > 0) else 1.0
                            placements[uid] = (fid, px, py, pz, ry, scale)
                p += 8 + sz

    bldg_mask = np.zeros((full_h, full_w), dtype=np.uint8)
    bldg_walls = np.zeros((full_h, full_w), dtype=np.float32)

    for fid, px, py, pz, ry, scale in placements.values():
        v, tris, nz, _fl, mat, _in = extract_wmo_world_tris(casc, fid, px, py, pz, ry, scale)
        if len(tris) == 0:
            continue

        rendered = (mat != 0xFF) & (mat != 0xFFFF)
        tri_z = v[tris][:, :, 2]
        tri_max_z = tri_z.max(axis=1)
        tri_min_z = tri_z.min(axis=1)
        tri_cx = v[tris][:, :, 0].mean(axis=1)
        tri_cy = v[tris][:, :, 1].mean(axis=1)
        hr = np.clip(((out_wx_max - tri_cx) / TILE_YARDS * 128.0).round().astype(np.int32), 0, h_max_row)
        hc = np.clip(((out_wy_max - tri_cy) / TILE_YARDS * 128.0).round().astype(np.int32), 0, h_max_col)
        tz = h_mosaic[hr, hc]

        keep = rendered & (tri_max_z >= tz + 1.2) & (tri_min_z <= tz + 48.0)
        if not keep.any():
            continue

        px_x = (out_wy_max - v[:, 1]) * px_per_yard
        px_y = (out_wx_max - v[:, 0]) * px_per_yard

        kt = tris[keep]
        tx2 = px_x[kt]
        ty2 = px_y[kt]
        area2 = np.abs(
            (tx2[:, 1] - tx2[:, 0]) * (ty2[:, 2] - ty2[:, 0])
            - (tx2[:, 2] - tx2[:, 0]) * (ty2[:, 1] - ty2[:, 0])
        )
        valid_tri = (
            (area2 >= 0.4)
            & (tx2.max(axis=1) >= 0)
            & (tx2.min(axis=1) < full_w)
            & (ty2.max(axis=1) >= 0)
            & (ty2.min(axis=1) < full_h)
        )
        if valid_tri.any():
            polys = np.stack([tx2[valid_tri], ty2[valid_tri]], axis=-1).round().astype(np.int32)
            cv2.fillPoly(bldg_mask, list(polys), 1)

        # Slice ground-floor interior & courtyard walls ~1.4 yd above terrain or courtyard base
        # Group floor elevation from upward WMO floor triangles near terrain
        wfloor = keep & (nz >= 0.58) & (tri_max_z <= tz + 26.0)
        wall_f = keep & (np.abs(nz) <= 0.45)
        if wall_f.any():
            # Compute local Z slice levels covering terrain + elevated courtyard floors
            base_z = float(np.median(tz[keep]))
            z_levels = [base_z + 1.35]
            if wfloor.any():
                wf_z = tri_z[wfloor].mean(axis=1)
                for q in (15, 50, 85):
                    zl = float(np.percentile(wf_z, q)) + 1.35
                    if all(abs(zl - prev) > 2.2 for prev in z_levels):
                        z_levels.append(zl)
            w_pts = v[tris[wall_f]]
            w_zmin = w_pts[:, :, 2].min(axis=1)
            w_zmax = w_pts[:, :, 2].max(axis=1)
            for z_s in z_levels:
                sel = (w_zmin < z_s) & (w_zmax > z_s)
                if not sel.any():
                    continue
                p1, p2 = slice_triangles_at_z(w_pts[sel], z_s)
                if len(p1) == 0:
                    continue
                x1 = ((out_wy_max - p1[:, 1]) * px_per_yard).round().astype(np.int32)
                y1 = ((out_wx_max - p1[:, 0]) * px_per_yard).round().astype(np.int32)
                x2 = ((out_wy_max - p2[:, 1]) * px_per_yard).round().astype(np.int32)
                y2 = ((out_wx_max - p2[:, 0]) * px_per_yard).round().astype(np.int32)
                in_b = (
                    (np.maximum(x1, x2) >= 0)
                    & (np.minimum(x1, x2) < full_w)
                    & (np.maximum(y1, y2) >= 0)
                    & (np.minimum(y1, y2) < full_h)
                    & ((x1 != x2) | (y1 != y2))
                )
                for ax, ay, bx, by in zip(x1[in_b], y1[in_b], x2[in_b], y2[in_b]):
                    cv2.line(bldg_walls, (int(ax), int(ay)), (int(bx), int(by)), 1.0, thickness=1, lineType=cv2.LINE_AA)

    cleaned = cv2.morphologyEx(bldg_mask, cv2.MORPH_CLOSE, np.ones((3, 3), dtype=np.uint8)) > 0
    return remove_small_components(cleaned, 36), np.clip(bldg_walls, 0.0, 1.0)


def _scan_road_batch(
    casc: LocalCASC,
    batch: list[tuple[int, int, int, int, int]],
) -> tuple[dict[int, int], dict[int, int], dict[int, list[float]], dict[int, int], dict[int, float], dict[int, list[float]]]:
    """Scan a batch of (cont, tx, ty, root_fid, tex0_fid) ADTs in a worker thread."""
    fid_base: dict[int, int] = defaultdict(int)
    fid_ovl: dict[int, int] = defaultdict(int)
    fid_nz: dict[int, list[float]] = defaultdict(list)
    fid_area: dict[int, int] = defaultdict(int)
    fid_perim: dict[int, float] = defaultdict(float)
    fid_dt: dict[int, list[float]] = defaultdict(list)

    for _cont, _tx, _ty, r_fid, t0_fid in batch:
        try:
            nz_g, _, _ = parse_adt_terrain(casc.read_fid(r_fid))
            nz128 = nz_g[:128, :128]
            t0 = casc.read_fid(t0_fid)
        except Exception:
            continue
        mdid: list[int] = []
        per_fid: dict[int, np.ndarray] = {}
        p, mcnk_idx = 0, 0
        while p + 8 <= len(t0):
            tag = t0[p : p + 4][::-1]
            sz = struct.unpack_from("<I", t0, p + 4)[0]
            if tag == b"MDID":
                mdid = list(struct.unpack_from(f"<{sz // 4}I", t0, p + 8))
            elif tag == b"MCNK":
                cx, cy = mcnk_idx % 16, mcnk_idx // 16
                mcnk_idx += 1
                layers, mcal = [], b""
                q, end = p + 8, p + 8 + sz
                while q + 8 <= end:
                    st = t0[q : q + 4][::-1]
                    ssz = struct.unpack_from("<I", t0, q + 4)[0]
                    if st == b"MCLY":
                        for li in range(ssz // 16):
                            tid, flg, ofs, _ = struct.unpack_from("<4I", t0, q + 8 + li * 16)
                            layers.append((tid, flg, ofs))
                    elif st == b"MCAL":
                        mcal = t0[q + 8 : q + 8 + ssz]
                    q += 8 + ssz
                for li, (tid, flg, ofs) in enumerate(layers):
                    if tid >= len(mdid):
                        continue
                    fid = mdid[tid]
                    if li == 0:
                        fid_base[fid] += 1
                    else:
                        fid_ovl[fid] += 1
                        if mcal and (flg & 0x100):
                            try:
                                a64 = _decode_mcal_layer(mcal, ofs, flg)
                            except Exception:
                                continue
                            a8 = cv2.resize(a64, (8, 8), interpolation=cv2.INTER_AREA)
                            g = per_fid.get(fid)
                            if g is None:
                                g = np.zeros((128, 128), dtype=np.float32)
                                per_fid[fid] = g
                            g[cy * 8 : (cy + 1) * 8, cx * 8 : (cx + 1) * 8] = np.maximum(
                                g[cy * 8 : (cy + 1) * 8, cx * 8 : (cx + 1) * 8], a8
                            )
            p += 8 + sz

        for fid, g in per_fid.items():
            m = (g > 0.30).astype(np.uint8)
            area = int(m.sum())
            if area < 10:
                continue
            dt = cv2.distanceTransform(m, cv2.DIST_L2, 3)
            cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
            fid_area[fid] += area
            fid_perim[fid] += sum(cv2.arcLength(c, True) for c in cnts)
            fid_dt[fid].append(float(np.percentile(dt[m > 0], 90)))
            fid_nz[fid].append(float(np.median(nz128[m > 0])))

    return dict(fid_base), dict(fid_ovl), dict(fid_nz), dict(fid_area), dict(fid_perim), dict(fid_dt)


def discover_road_textures(
    casc: LocalCASC, wdt_maids: dict[int, bytes], max_workers: int = 3
) -> set[int]:
    """Identify cobble/dirt road overlay textures across all continents via geometry + color."""
    tasks: list[tuple[int, int, int, int, int]] = []
    for cont, maid in wdt_maids.items():
        for ty in range(64):
            for tx in range(64):
                r_fid, _, _, t0_fid = struct.unpack_from("<4I", maid, (ty * 64 + tx) * 32)
                if r_fid and t0_fid and r_fid in casc.fid_to_ckey and t0_fid in casc.fid_to_ckey:
                    tasks.append((cont, tx, ty, r_fid, t0_fid))

    batch_sz = max(1, (len(tasks) + max_workers - 1) // max_workers)
    batches = [tasks[i : i + batch_sz] for i in range(0, len(tasks), batch_sz)]

    tot_base: dict[int, int] = defaultdict(int)
    tot_ovl: dict[int, int] = defaultdict(int)
    tot_nz: dict[int, list[float]] = defaultdict(list)
    tot_area: dict[int, int] = defaultdict(int)
    tot_perim: dict[int, float] = defaultdict(float)
    tot_dt: dict[int, list[float]] = defaultdict(list)

    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        for b, o, nz_d, ar_d, pe_d, dt_d in ex.map(lambda batch: _scan_road_batch(casc, batch), batches):
            for k, v in b.items():
                tot_base[k] += v
            for k, v in o.items():
                tot_ovl[k] += v
            for k, v in nz_d.items():
                tot_nz[k].extend(v)
            for k, v in ar_d.items():
                tot_area[k] += v
            for k, v in pe_d.items():
                tot_perim[k] += v
            for k, v in dt_d.items():
                tot_dt[k].extend(v)

    roads = set(KNOWN_ROAD_TEX_FIDS)
    for fid, area in tot_area.items():
        ovl = tot_ovl[fid]
        base = tot_base[fid]
        if ovl < 25 or area <= 0 or not tot_nz[fid] or not tot_dt[fid]:
            continue
        br = base / max(1, base + ovl)
        mnz = float(np.median(tot_nz[fid]))
        w_yd = float(np.median(tot_dt[fid])) * 2.0 * (TILE_YARDS / 128.0)
        thin = tot_perim[fid] / max(1.0, float(area))
        if br >= 0.15 or mnz < 0.93 or w_yd > 18.0 or thin < 0.62:
            continue
        if fid not in casc.fid_to_ckey:
            continue
        try:
            im = np.array(casc.read_blp_rgba(fid), dtype=np.float32)
        except Exception:
            continue
        rm, gm, bm = float(im[:, :, 0].mean()), float(im[:, :, 1].mean()), float(im[:, :, 2].mean())
        lum = 0.299 * rm + 0.587 * gm + 0.114 * bm
        if lum >= 55.0 and rm >= gm - 4.0 and bm >= 38.0 and bm >= 0.35 * max(rm, gm, 1.0):
            roads.add(fid)

    return roads


def _propagate_ocean_cells(water_mosaic: np.ndarray, has_adt: np.ndarray) -> None:
    """Extend open ocean flags into unpopulated deep-sea border ADTs so shorelines never seam."""
    ny, nx = has_adt.shape
    filled = has_adt.copy()
    for _ in range(2):
        updates: list[tuple[int, int]] = []
        for yi in range(ny):
            for xi in range(nx):
                if filled[yi, xi]:
                    continue
                w_hits = 0
                w_tot = 0
                if yi > 0 and filled[yi - 1, xi]:
                    edge = water_mosaic[yi * 128 - 1, xi * 128 : (xi + 1) * 128]
                    w_hits += int((edge > 0).sum())
                    w_tot += len(edge)
                if yi + 1 < ny and filled[yi + 1, xi]:
                    edge = water_mosaic[(yi + 1) * 128, xi * 128 : (xi + 1) * 128]
                    w_hits += int((edge > 0).sum())
                    w_tot += len(edge)
                if xi > 0 and filled[yi, xi - 1]:
                    edge = water_mosaic[yi * 128 : (yi + 1) * 128, xi * 128 - 1]
                    w_hits += int((edge > 0).sum())
                    w_tot += len(edge)
                if xi + 1 < nx and filled[yi, xi + 1]:
                    edge = water_mosaic[yi * 128 : (yi + 1) * 128, (xi + 1) * 128]
                    w_hits += int((edge > 0).sum())
                    w_tot += len(edge)
                if w_tot > 0 and (w_hits / w_tot) >= 0.35:
                    updates.append((yi, xi))
        if not updates:
            break
        for yi, xi in updates:
            water_mosaic[yi * 128 : (yi + 1) * 128, xi * 128 : (xi + 1) * 128] = 1
            filled[yi, xi] = True


def render_outdoor_window(
    casc: LocalCASC,
    maid_data: bytes,
    tx_list: list[int],
    ty_list: list[int],
    road_fids: set[int],
    tile_px: int = TILE_PX,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Render an (len(tx_list) x len(ty_list)) ADT block with full CAD contour/WMO/hatch fidelity."""
    nx, ny = len(tx_list), len(ty_list)
    ss = SS_FACTOR
    hi_tile = tile_px * ss
    full_w, full_h = nx * hi_tile, ny * hi_tile

    nz_mosaic = np.ones((ny * 128 + 1, nx * 128 + 1), dtype=np.float32)
    h_mosaic = np.zeros((ny * 128 + 1, nx * 128 + 1), dtype=np.float32)
    water_mosaic = np.zeros((ny * 128, nx * 128), dtype=np.uint8)
    has_adt = np.zeros((ny, nx), dtype=bool)
    road_mosaic = np.zeros((full_h, full_w), dtype=np.float32)

    for yi, ty in enumerate(ty_list):
        for xi, tx in enumerate(tx_list):
            root_fid, _, _, tex0_fid = struct.unpack_from("<4I", maid_data, (ty * 64 + tx) * 32)
            if root_fid and root_fid in casc.fid_to_ckey:
                try:
                    nz_g, h_g, w_g = parse_adt_terrain(casc.read_fid(root_fid))
                    nz_mosaic[yi * 128 : yi * 128 + 129, xi * 128 : xi * 128 + 129] = nz_g
                    h_mosaic[yi * 128 : yi * 128 + 129, xi * 128 : xi * 128 + 129] = h_g
                    water_mosaic[yi * 128 : (yi + 1) * 128, xi * 128 : (xi + 1) * 128] = w_g
                    has_adt[yi, xi] = True
                except Exception:
                    pass
            if tex0_fid and tex0_fid in casc.fid_to_ckey:
                try:
                    rg = parse_tex0_roads(casc.read_fid(tex0_fid), road_fids)
                    road_mosaic[yi * hi_tile : (yi + 1) * hi_tile, xi * hi_tile : (xi + 1) * hi_tile] = cv2.resize(
                        rg, (hi_tile, hi_tile), interpolation=cv2.INTER_LINEAR
                    )
                except Exception:
                    pass

    _propagate_ocean_cells(water_mosaic, has_adt)

    nz_full = cv2.resize(nz_mosaic, (full_w, full_h), interpolation=cv2.INTER_CUBIC)
    del nz_mosaic
    h_full = cv2.resize(h_mosaic, (full_w, full_h), interpolation=cv2.INTER_CUBIC)
    water_mask = cv2.resize(
        water_mosaic.astype(np.float32), (full_w, full_h), interpolation=cv2.INTER_LINEAR
    ) >= 0.45
    del water_mosaic

    bldg_mask, bldg_walls = rasterize_outdoor_wmos(
        casc, maid_data, tx_list, ty_list, h_mosaic, full_w, full_h, hi_tile
    )
    del h_mosaic

    dst_p = np.zeros((full_h, full_w, 3), dtype=np.float32)
    dst_a = np.zeros((full_h, full_w), dtype=np.float32)

    steep_mask = remove_small_components((nz_full < 0.77) & (~water_mask) & (~bldg_mask), 450)
    slope_band = (nz_full >= 0.77) & (nz_full < 0.945) & (~water_mask) & (~bldg_mask)
    del nz_full
    if slope_band.any():
        h_q = np.floor(h_full / 15.0).astype(np.int32)
        isolines = np.zeros((full_h, full_w), dtype=bool)
        isolines[:-1, :] |= h_q[:-1, :] != h_q[1:, :]
        isolines[:, :-1] |= h_q[:, :-1] != h_q[:, 1:]
        isolines &= slope_band
        if isolines.any():
            over_premul(dst_p, dst_a, (166.0, 152.0, 128.0), isolines.astype(np.float32) * 0.14)
        del h_q, isolines
    del h_full, slope_band

    if water_mask.any():
        over_premul(dst_p, dst_a, (22.0, 36.0, 50.0), water_mask.astype(np.float32) * 0.16)
        w_cnts = extract_contours(water_mask, eps_px=1.2, min_area=64.0)
        composite_aa_contours(
            dst_p, dst_a, w_cnts, (142.0, 176.0, 198.0), peak_alpha=0.76, thickness=2, halo_thickness=4, halo_alpha=0.38
        )

    road_blur = cv2.GaussianBlur(road_mosaic, (0, 0), sigmaX=2.2)
    road_mask = remove_small_components((road_blur > 0.30) & (~water_mask) & (~bldg_mask), 180)
    del road_mosaic, road_blur
    if road_mask.any():
        over_premul(dst_p, dst_a, (54.0, 48.0, 40.0), road_mask.astype(np.float32) * 0.09)
        r_cnts = extract_contours(road_mask, eps_px=1.6, min_area=64.0)
        composite_aa_contours(
            dst_p, dst_a, r_cnts, (186.0, 170.0, 142.0), peak_alpha=0.52, thickness=2, halo_thickness=4, halo_alpha=0.24
        )

    if steep_mask.any():
        steep_smooth = cv2.GaussianBlur(steep_mask.astype(np.float32), (0, 0), sigmaX=1.8) >= 0.5
        dist_cliff = np.where(steep_smooth, cv2.distanceTransform(steep_smooth.astype(np.uint8), cv2.DIST_L2, 5), 0.0)
        composite_diagonal_hatch(
            dst_p, dst_a, dist_cliff, wash_fade=56.0, stripe_fade=72.0, wash_alpha=0.38, stripe_alpha=0.28,
            angle_deg=-66.0, period_px=8.6, sharpness=3.0, max_dist=140.0,
        )
        s_cnts = extract_contours(steep_smooth, eps_px=1.35, min_area=48.0)
        composite_aa_contours(
            dst_p, dst_a, s_cnts, (206.0, 190.0, 158.0), peak_alpha=0.80, thickness=2, halo_thickness=4, halo_alpha=0.48
        )
        del steep_smooth, dist_cliff
    del steep_mask

    if bldg_mask.any():
        over_premul(dst_p, dst_a, (78.0, 58.0, 38.0), bldg_mask.astype(np.float32) * 0.24)
        if bldg_walls.any():
            masked_w = bldg_walls * bldg_mask.astype(np.float32)
            over_premul(dst_p, dst_a, (10.0, 12.0, 16.0), np.clip(masked_w * 0.36, 0.0, 1.0))
            over_premul(dst_p, dst_a, (224.0, 184.0, 124.0), np.clip(masked_w * 0.62, 0.0, 1.0))
            del masked_w
        b_cnts = extract_contours(bldg_mask, eps_px=0.90, min_area=24.0)
        composite_aa_contours(
            dst_p, dst_a, b_cnts, (226.0, 186.0, 124.0), peak_alpha=0.92, thickness=2, halo_thickness=4, halo_alpha=0.58
        )
    del bldg_walls

    ocean_only = np.zeros((ny, nx), dtype=bool)
    for yi in range(ny):
        y0, y1 = yi * hi_tile, (yi + 1) * hi_tile
        for xi in range(nx):
            x0, x1 = xi * hi_tile, (xi + 1) * hi_tile
            if (
                has_adt[yi, xi]
                and water_mask[y0:y1, x0:x1].all()
                and not bldg_mask[y0:y1, x0:x1].any()
                and not road_mask[y0:y1, x0:x1].any()
            ):
                ocean_only[yi, xi] = True
    del water_mask, bldg_mask, road_mask

    overlay_rgba = premul_to_rgba(dst_p, dst_a, downsample=ss)
    del dst_p, dst_a
    return overlay_rgba, has_adt, ocean_only


def _render_chunk_worker(
    job: tuple[
        LocalCASC,
        bytes,
        int,
        str,
        int,
        int,
        int,
        int,
        set[int],
        int,
        list[tuple[int, int]] | None,
        int,
    ],
) -> tuple[dict[tuple[int, int], str], dict[tuple[int, int], np.ndarray]]:
    """Worker: render a (core + 1-ADT halo) block, sequentially encode non-ocean core tiles to BLP2 DXT5."""
    casc, maid_data, _cont, prefix, cx0, cx1, cy0, cy1, road_fids, tile_px, preview_coords, magick_threads = job

    bx0, bx1 = max(0, cx0 - 1), min(63, cx1 + 1)
    by0, by1 = max(0, cy0 - 1), min(63, cy1 + 1)
    tx_list = list(range(bx0, bx1 + 1))
    ty_list = list(range(by0, by1 + 1))

    overlay_rgba, has_adt, ocean_only = render_outdoor_window(
        casc, maid_data, tx_list, ty_list, road_fids, tile_px=tile_px
    )

    saved: dict[tuple[int, int], str] = {}
    preview_tiles: dict[tuple[int, int], np.ndarray] = {}
    want_prev = set(preview_coords or ())

    for yi, ty in enumerate(ty_list):
        if ty < cy0 or ty > cy1:
            continue
        for xi, tx in enumerate(tx_list):
            if tx < cx0 or tx > cx1 or not has_adt[yi, xi]:
                continue
            sub = overlay_rgba[yi * tile_px : (yi + 1) * tile_px, xi * tile_px : (xi + 1) * tile_px]
            if (tx, ty) in want_prev:
                preview_tiles[(tx, ty)] = np.array(sub, copy=True)
            if sub[:, :, 3].max() == 0:
                continue
            if ocean_only[yi, xi] and int(sub[:, :, 3].max()) <= 45:
                continue
            fname = f"{prefix}_{tx}_{ty}.blp"
            save_blp2_dxt5(MEDIA_OUT / fname, sub, magick_threads=magick_threads)
            saved[(tx, ty)] = fname

    del overlay_rgba, ocean_only, has_adt
    return saved, preview_tiles


def build_continent_chunked(
    casc: LocalCASC,
    cont: int,
    prefix: str,
    label: str,
    maid_data: bytes,
    road_fids: set[int],
    tile_px: int = TILE_PX,
    max_workers: int = 12,
    max_rss_mb: int = 28672,
    magick_threads: int = 2,
    preview_coords: list[tuple[int, int]] | None = None,
) -> tuple[dict[tuple[int, int], str], dict[tuple[int, int], np.ndarray]]:
    """Build an entire continent in bounded haloed chunks at 512px BLP2 DXT5."""
    populated: set[tuple[int, int]] = set()
    for ty in range(64):
        for tx in range(64):
            r_fid = struct.unpack_from("<I", maid_data, (ty * 64 + tx) * 32)[0]
            if r_fid:
                populated.add((tx, ty))
    if not populated:
        return {}, {}

    min_tx = min(tx for tx, _ in populated)
    max_tx = max(tx for tx, _ in populated)
    min_ty = min(ty for _, ty in populated)
    max_ty = max(ty for _, ty in populated)

    chunk_jobs = []
    for cy0 in range(min_ty, max_ty + 1, CHUNK_CORE_TILES):
        cy1 = min(max_ty, cy0 + CHUNK_CORE_TILES - 1)
        for cx0 in range(min_tx, max_tx + 1, CHUNK_CORE_TILES):
            cx1 = min(max_tx, cx0 + CHUNK_CORE_TILES - 1)
            has_any = any((tx, ty) in populated for ty in range(cy0, cy1 + 1) for tx in range(cx0, cx1 + 1))
            if has_any:
                chunk_jobs.append(
                    (casc, maid_data, cont, prefix, cx0, cx1, cy0, cy1, road_fids, tile_px, preview_coords, magick_threads)
                )

    t0 = time.perf_counter()
    print(
        f"Building continent {cont} ({label}): {len(populated)} ADTs across {len(chunk_jobs)} "
        f"bounded {CHUNK_CORE_TILES}x{CHUNK_CORE_TILES} haloed chunks (workers={max_workers}, cap={max_rss_mb} MB)..."
    )
    saved_all: dict[tuple[int, int], str] = {}
    previews_all: dict[tuple[int, int], np.ndarray] = {}
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        job_iter = iter(chunk_jobs)
        pending = set()
        for _ in range(max_workers):
            j = next(job_iter, None)
            if j is None:
                break
            pending.add(ex.submit(_render_chunk_worker, j))
        done_cnt = 0
        while pending:
            done, pending = wait(pending, return_when=FIRST_COMPLETED)
            for fut in done:
                c_saved, c_prev = fut.result()
                saved_all.update(c_saved)
                previews_all.update(c_prev)
                done_cnt += 1
                rss_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0
                if rss_mb > max_rss_mb:
                    for pf in pending:
                        pf.cancel()
                    raise MemoryError(f"RSS {rss_mb:.0f} MB exceeded --max-rss-mb={max_rss_mb}")
                if done_cnt % 8 == 0:
                    gc.collect()
                if done_cnt % 8 == 0 or done_cnt == len(chunk_jobs):
                    print(
                        f"  [{label}] {done_cnt}/{len(chunk_jobs)} chunks "
                        f"({len(saved_all)} tiles, rss={rss_mb:.0f} MB, {time.perf_counter() - t0:.1f}s)"
                    )
                nj = next(job_iter, None)
                if nj is not None:
                    pending.add(ex.submit(_render_chunk_worker, nj))
    return saved_all, previews_all


def build_outdoor(
    casc: LocalCASC,
    wdt_bytes: bytes,
    tile_px: int = TILE_PX,
    tile_jobs: list[tuple[Path, np.ndarray]] | None = None,
) -> tuple[dict[tuple[int, int], str], np.ndarray]:
    """PoC subset builder (Tirisfal/Deathknell) using shared render_outdoor_window."""
    maid_data = wdt_bytes[wdt_bytes.index(b"DIAM") + 8 :]
    tx_list = list(OUTDOOR_TX_RANGE)
    ty_list = list(OUTDOOR_TY_RANGE)
    overlay_rgba, _has, _ocean = render_outdoor_window(
        casc, maid_data, tx_list, ty_list, ROAD_TEX_FIDS, tile_px=tile_px
    )
    saved_tiles: dict[tuple[int, int], str] = {}
    for yi, ty in enumerate(ty_list):
        for xi, tx in enumerate(tx_list):
            sub = overlay_rgba[yi * tile_px : (yi + 1) * tile_px, xi * tile_px : (xi + 1) * tile_px]
            if sub[:, :, 3].max() > 0:
                fname = f"ek_{tx}_{ty}.blp"
                if tile_jobs is not None:
                    tile_jobs.append((MEDIA_OUT / fname, np.array(sub, copy=True)))
                else:
                    save_blp2_dxt5(MEDIA_OUT / fname, sub)
                saved_tiles[(tx, ty)] = fname
    return saved_tiles, overlay_rgba


def composite_wmo_pieces(
    casc: LocalCASC,
    pieces: list[tuple[int, float, float, float, float, float, float]]
    | list[tuple[int, float, float, float, float, float, float, bool]],
    wx_max: float,
    wy_max: float,
    width: int,
    height: int,
    px_per_yard: float,
    blp_cache: dict[tuple[int, bool], np.ndarray] | None = None,
) -> Image.Image:
    """Composite WMO minimap textures matching OpenMap Close.lua TexCoord+Rotation semantics."""
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    cache: dict[tuple[int, bool, float, float, int], np.ndarray] = {}
    mend_dir = ADDONS_DIR / "OpenMap/Media/Textures/Forever/MapCaveMend"

    for piece in pieces:
        fid, cx, cy, side, rot, u1, v0 = piece[:7]
        use_mend = bool(piece[7]) if len(piece) > 7 else False
        px_side = max(4, int(round(side * px_per_yard)))
        key = (fid, use_mend, u1, v0, px_side)
        if key not in cache:
            src_key = (fid, use_mend)
            if blp_cache is not None and src_key in blp_cache:
                src = blp_cache[src_key]
            else:
                mend_path = mend_dir / f"{fid}.tga"
                if use_mend and mend_path.exists():
                    with Image.open(mend_path) as mim:
                        src = np.array(mim.convert("RGBA"))
                else:
                    src = np.array(casc.read_blp_rgba(fid))
                if blp_cache is not None:
                    if len(blp_cache) > 512:
                        blp_cache.clear()
                    blp_cache[src_key] = src
            bh, bw = src.shape[:2]
            gs = (np.arange(px_side, dtype=np.float32) + 0.5) / px_side
            ux = gs * u1
            vy = v0 + gs * (1.0 - v0)
            ux_grid, vy_grid = np.meshgrid(ux, vy)
            valid = (ux_grid >= 0.0) & (ux_grid <= 1.0) & (vy_grid >= 0.0) & (vy_grid <= 1.0)
            map_x = np.clip(ux_grid * (bw - 1), 0.0, bw - 1).astype(np.float32)
            map_y = np.clip(vy_grid * (bh - 1), 0.0, bh - 1).astype(np.float32)
            sampled = cv2.remap(src, map_x, map_y, cv2.INTER_LINEAR)
            sampled[~valid] = 0
            cache[key] = sampled

        piece_im = Image.fromarray(cache[key], mode="RGBA")
        rot_deg = math.degrees(rot)
        if abs(rot_deg) > 1e-4:
            piece_im = piece_im.rotate(
                rot_deg, resample=Image.Resampling.BILINEAR, expand=True
            )
        dst_x = int(round((wy_max - cy) * px_per_yard - piece_im.width * 0.5))
        dst_y = int(round((wx_max - cx) * px_per_yard - piece_im.height * 0.5))
        sx0 = max(0, -dst_x)
        sy0 = max(0, -dst_y)
        dx0 = max(0, dst_x)
        dy0 = max(0, dst_y)
        sx1 = min(piece_im.width, width - dst_x)
        sy1 = min(piece_im.height, height - dst_y)
        if sx1 > sx0 and sy1 > sy0:
            canvas.alpha_composite(piece_im, (dx0, dy0), (sx0, sy0, sx1, sy1))
    return canvas


def parse_wmo_pieces_string(pics_str: str) -> list[tuple[int, float, float, float, float, float, float, bool]]:
    toks = [t.strip() for t in pics_str.split(",") if t.strip()]
    out = []
    for i in range(0, len(toks), 7):
        fid_tok = toks[i]
        use_mend = fid_tok.startswith("M")
        m = re.search(r"(\d+)", fid_tok)
        assert m, f"Bad FID token {fid_tok!r}"
        out.append(
            (
                int(m.group(1)),
                float(toks[i + 1]),
                float(toks[i + 2]),
                float(toks[i + 3]),
                float(toks[i + 4]),
                float(toks[i + 5]),
                float(toks[i + 6]),
                use_mend,
            )
        )
    return out


def build_city_from_caveminimap(
    casc: LocalCASC,
    ui_map_id: int,
    cfg: dict[str, object],
    cave_txt: str,
    maid_azeroth: bytes,
    tile_px: int = TILE_PX,
    tile_jobs: list[tuple[Path, np.ndarray]] | None = None,
) -> tuple[dict[str, object], np.ndarray]:
    """Build subterranean capital city from OpenMap CaveMinimap pieces + 3D WMO wall slicing."""
    name = str(cfg["name"])
    line = [l for l in cave_txt.splitlines() if f"[{ui_map_id}] =" in l][0]
    inner = line.split("{", 2)[2].rsplit("}", 2)[0]
    pieces = parse_wmo_pieces_string(inner)

    wx_max = float(cfg["wx_max"])  # type: ignore[arg-type]
    wx_min = float(cfg["wx_min"])  # type: ignore[arg-type]
    wy_max = float(cfg["wy_max"])  # type: ignore[arg-type]
    wy_min = float(cfg["wy_min"])  # type: ignore[arg-type]
    ss = SS_FACTOR
    hi_tile = tile_px * ss
    px_per_yard = hi_tile / 128.0
    size = 6 * hi_tile

    comp_im = composite_wmo_pieces(
        casc, pieces, wx_max, wy_max, size, size, px_per_yard
    )
    arr = np.array(comp_im)
    walkable = cv2.morphologyEx(
        (arr[:, :, 3] > 26).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), dtype=np.uint8)
    ) > 0
    walkable = remove_small_components(walkable, 120)

    num, _, stats, _ = cv2.connectedComponentsWithStats(walkable.astype(np.uint8), connectivity=8)
    areas = sorted((stats[i, cv2.CC_STAT_AREA] for i in range(1, num)), reverse=True)
    largest_share = (areas[0] / max(1, sum(areas))) if areas else 0.0
    print(f"City {name} ({ui_map_id}) stitched walkable share: {largest_share:.3f} (components={num - 1})")
    if largest_share < 0.70:
        raise RuntimeError(f"City {name} WMO stitching fragmented (largest_share={largest_share:.3f})")

    interior_lines = np.zeros((size, size), dtype=np.float32)
    target_wmo = int(cfg["wmo_fid"])  # type: ignore[arg-type]
    max_z = cfg["max_walk_z"]
    tx0, tx1 = cfg["tx_range"]  # type: ignore[misc]
    ty0, ty1 = cfg["ty_range"]  # type: ignore[misc]
    found_wmo = False
    for ty in range(ty0, ty1):
        if found_wmo:
            break
        for tx in range(tx0, tx1):
            ob_fid = struct.unpack_from("<I", maid_azeroth, (ty * 64 + tx) * 32 + 4)[0]
            if not ob_fid or ob_fid not in casc.fid_to_ckey:
                continue
            ob = casc.read_fid(ob_fid)
            p = 0
            while p + 8 <= len(ob):
                t = ob[p : p + 4][::-1]
                sz = struct.unpack_from("<I", ob, p + 4)[0]
                if t == b"MODF":
                    for k in range(0, sz, 64):
                        wf, _uid, px, py, pz, _rx, ry, _rz, _lx, _ly, _lz, _ux, _uy, _uz, flg, _did, _ns, sc = struct.unpack_from(
                            "<II12fHHHH", ob, p + 8 + k
                        )
                        if wf == target_wmo:
                            scale = (sc / 1024.0) if ((flg & 4) and sc > 0) else 1.0
                            v, tris, nz, _fl, mat, is_in = extract_wmo_world_tris(
                                casc,
                                wf,
                                px,
                                py,
                                pz,
                                ry,
                                scale,
                                indoor_only=True,
                                max_walk_z=float(max_z) if max_z is not None else None,
                            )
                            _w3d, interior_lines = build_wmo_floorplan_masks(
                                v,
                                tris,
                                nz,
                                mat,
                                is_in,
                                wx_max,
                                wy_max,
                                size,
                                size,
                                px_per_yard,
                                indoor_only=True,
                                max_walk_z=(float(max_z) - 1.0) if max_z is not None else None,
                                slice_h=1.25,
                            )
                            found_wmo = True
                            break
                p += 8 + sz

    canal_mask = None
    if cfg.get("detect_canals"):
        r_f = arr[:, :, 0].astype(np.float32)
        g_f = arr[:, :, 1].astype(np.float32)
        b_f = arr[:, :, 2].astype(np.float32)
        canal_raw = (g_f > r_f + 22.0) & (g_f > b_f + 18.0) & (r_f < 68.0) & (g_f > 72.0) & walkable
        canal_mask = remove_small_components(
            cv2.morphologyEx(canal_raw.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), dtype=np.uint8)) > 0,
            2400,
        )

    overlay_rgba = render_architectural_map(
        walkable,
        interior_lines=interior_lines,
        canal_mask=canal_mask,
        downsample=ss,
        max_hatch_dist=140.0,
        wall_thickness=3,
        halo_thickness=6,
        island_max_area=12000,
    )

    tiles = {}
    for row in range(6):
        for col in range(6):
            sub = overlay_rgba[row * tile_px : (row + 1) * tile_px, col * tile_px : (col + 1) * tile_px]
            if sub[:, :, 3].max() > 0:
                fname = f"city_{ui_map_id}_{col}_{row}.blp"
                if tile_jobs is not None:
                    tile_jobs.append((MEDIA_OUT / fname, np.array(sub, copy=True)))
                else:
                    save_blp2_dxt5(MEDIA_OUT / fname, sub)
                tiles[(col, row)] = fname

    meta: dict[str, object] = {
        "uiMapID": ui_map_id,
        "cont": int(cfg["cont"]),  # type: ignore[arg-type]
        "name": name,
        "maxX": wx_max,
        "minX": wx_min,
        "maxY": wy_max,
        "minY": wy_min,
        "cols": 6,
        "rows": 6,
        "stepYards": 128.0,
        "tiles": tiles,
    }
    return meta, overlay_rgba


def build_cities(
    casc: LocalCASC,
    cave_txt: str,
    maid_azeroth: bytes,
    city_ids: tuple[int, ...] = (1455, 1458),
    tile_px: int = TILE_PX,
    tile_jobs: list[tuple[Path, np.ndarray]] | None = None,
) -> tuple[dict[int, dict[str, object]], dict[int, np.ndarray]]:
    metas: dict[int, dict[str, object]] = {}
    rgbas: dict[int, np.ndarray] = {}
    for mid in city_ids:
        meta, rgba = build_city_from_caveminimap(
            casc, mid, SUBTERRANEAN_CITIES[mid], cave_txt, maid_azeroth, tile_px=tile_px, tile_jobs=tile_jobs
        )
        metas[mid] = meta
        rgbas[mid] = rgba
    return metas, rgbas


def build_undercity(
    casc: LocalCASC,
    cave_txt: str,
    maid_azeroth: bytes,
    tile_px: int = TILE_PX,
    tile_jobs: list[tuple[Path, np.ndarray]] | None = None,
) -> tuple[dict[str, object], np.ndarray]:
    return build_city_from_caveminimap(
        casc, 1458, SUBTERRANEAN_CITIES[1458], cave_txt, maid_azeroth, tile_px=tile_px, tile_jobs=tile_jobs
    )


def build_scarlet_monastery(
    casc: LocalCASC,
    tile_px: int = TILE_PX,
    tile_jobs: list[tuple[Path, np.ndarray]] | None = None,
) -> tuple[dict[str, object], dict[str, np.ndarray]]:
    """Extract & render all 4 Scarlet Monastery dungeon wings (instanceID 189, WDT 788662) from 3D WMOs."""
    wdt_bytes = casc.read_fid(SM_WDT_FID)
    maid = wdt_bytes[wdt_bytes.index(b"DIAM") + 8 :]

    placements: dict[int, tuple[int, float, float, float, float, float]] = {}
    for ty in range(64):
        for tx in range(64):
            obj0_fid = struct.unpack_from("<I", maid, (ty * 64 + tx) * 32 + 4)[0]
            if not obj0_fid or obj0_fid not in casc.fid_to_ckey:
                continue
            obj0 = casc.read_fid(obj0_fid)
            p = 0
            while p + 8 <= len(obj0):
                t = obj0[p : p + 4][::-1]
                sz = struct.unpack_from("<I", obj0, p + 4)[0]
                if t == b"MODF":
                    for k in range(0, sz, 64):
                        wf, uid, px, py, pz, _rx, ry, _rz, _lx, _ly, _lz, _ux, _uy, _uz, flg, _did, _ns, sc = struct.unpack_from(
                            "<II12fHHHH", obj0, p + 8 + k
                        )
                        if wf in SM_WINGS and uid not in placements:
                            scale = (sc / 1024.0) if ((flg & 4) and sc > 0) else 1.0
                            placements[uid] = (wf, px, py, pz, ry, scale)
                p += 8 + sz

    ss = SS_FACTOR
    step = SM_STEP_YARDS
    hi_tile = tile_px * ss
    px_per_yard = hi_tile / step
    margin = 20.0

    wings_meta: list[dict[str, object]] = []
    previews: dict[str, dict[str, object]] = {}

    for _uid, (wf, px, py, pz, ry, scale) in sorted(placements.items(), key=lambda kv: SM_WINGS[kv[1][0]][1]):
        short, uimap_id, full_name, max_z = SM_WINGS[wf]
        v, tris, nz, _fl, mat, is_in = extract_wmo_world_tris(
            casc, wf, px, py, pz, ry, scale, indoor_only=False, max_walk_z=max_z
        )
        rendered = (mat != 0xFF) & (mat != 0xFFFF)
        tmz = v[tris][:, :, 2].mean(axis=1)
        walk_t = rendered & (nz >= 0.50)
        in_walk = walk_t & is_in
        if in_walk.any():
            z_cap = float(np.percentile(tmz[in_walk], 95)) + 6.5
            walk_t = walk_t & (is_in | ((nz >= 0.58) & (tmz <= z_cap)))
        if max_z is not None:
            walk_t = walk_t & (tmz <= max_z)

        wt = tris[walk_t]
        minX = float(v[wt][:, :, 0].min())
        maxX = float(v[wt][:, :, 0].max())
        minY = float(v[wt][:, :, 1].min())
        maxY = float(v[wt][:, :, 1].max())

        # Snap wing grid to SM_STEP_YARDS boundaries with hatch margin
        gx_min = math.floor((minX - margin) / step) * step
        gx_max = math.ceil((maxX + margin) / step) * step
        gy_min = math.floor((minY - margin) / step) * step
        gy_max = math.ceil((maxY + margin) / step) * step
        cols = int(round((gy_max - gy_min) / step))
        rows = int(round((gx_max - gx_min) / step))

        walkable, interior_lines = build_wmo_floorplan_masks(
            v, tris, nz, mat, is_in,
            gx_max, gy_max, cols * hi_tile, rows * hi_tile, px_per_yard,
            indoor_only=False, max_walk_z=max_z, slice_h=1.25,
        )

        # Verify connected share
        num, _, stats, _ = cv2.connectedComponentsWithStats(walkable.astype(np.uint8), connectivity=8)
        areas = sorted((int(stats[i, cv2.CC_STAT_AREA]) for i in range(1, num)), reverse=True)
        share = areas[0] / max(1, sum(areas)) if areas else 0.0
        print(
            f"SM {short:9s} ({uimap_id}): wx={minX:.1f}..{maxX:.1f} wy={minY:.1f}..{maxY:.1f} "
            f"grid={cols}x{rows} cc_share={share:.3f}"
        )

        rgba = render_architectural_map(
            walkable,
            interior_lines=interior_lines,
            canal_mask=None,
            downsample=ss,
            max_hatch_dist=180.0,
            wall_thickness=3,
            halo_thickness=6,
            island_max_area=20000,
        )

        tiles: dict[tuple[int, int], str] = {}
        for r in range(rows):
            for c in range(cols):
                sub = rgba[r * tile_px : (r + 1) * tile_px, c * tile_px : (c + 1) * tile_px]
                if sub[:, :, 3].max() > 0:
                    fname = f"sm_{short}_{c}_{r}.blp"
                    if tile_jobs is not None:
                        tile_jobs.append((MEDIA_OUT / fname, np.array(sub, copy=True)))
                    else:
                        save_blp2_dxt5(MEDIA_OUT / fname, sub)
                    tiles[(c, r)] = fname

        w_meta = {
            "id": short,
            "name": full_name,
            "uiMapID": uimap_id,
            "minX": minX - 12.0,
            "maxX": maxX + 12.0,
            "minY": minY - 12.0,
            "maxY": maxY + 12.0,
            "gridMinX": gx_min,
            "gridMaxX": gx_max,
            "gridMinY": gy_min,
            "gridMaxY": gy_max,
            "cols": cols,
            "rows": rows,
            "stepYards": step,
            "tiles": tiles,
        }
        wings_meta.append(w_meta)
        previews[short] = {
            "rgba": rgba,
            "maxX": gx_max,
            "minX": gx_min,
            "maxY": gy_max,
            "minY": gy_min,
        }

    # Exact boss & dungeon quest locations derived from 3D WMO rooms & Questie/FDJ metadata
    sm_pins = [
        # Graveyard (302)
        {"uiMapID": 302, "wx": 1695.0, "wy": 1054.0, "kind": "boss", "title": "interrogator vishas", "subtitle": "chamber of atonement (boss)"},
        {"uiMapID": 302, "wx": 1812.0, "wy": 1417.0, "kind": "boss", "title": "bloodmage thalnos", "subtitle": "honor's tomb crypt (boss)"},
        {"uiMapID": 302, "wx": 1735.0, "wy": 1098.0, "kind": "quest_start", "title": "vorrel's revenge", "subtitle": "vorrel sengutz (horde quest)", "faction": "H", "questId": 1051},
        # Library (303)
        {"uiMapID": 303, "wx": 274.0, "wy": -147.0, "kind": "boss", "title": "houndmaster loksey", "subtitle": "huntsman's cloister kennel (boss)"},
        {"uiMapID": 303, "wx": 149.0, "wy": -429.0, "kind": "boss", "title": "arcanist doan", "subtitle": "athenaeum rotunda (boss)"},
        {"uiMapID": 303, "wx": 264.0, "wy": -330.0, "kind": "quest_obj", "title": "mythology of the titans", "subtitle": "gallery bookshelf (alliance objective)", "faction": "A", "questId": 1050},
        {"uiMapID": 303, "wx": 264.0, "wy": -395.0, "kind": "quest_obj", "title": "compendium of the fallen", "subtitle": "reading room shelf (horde objective)", "faction": "H", "questId": 1049},
        # Armory (304)
        {"uiMapID": 304, "wx": 1965.0, "wy": -431.0, "kind": "boss", "title": "herod", "subtitle": "hall of champions arena (boss)"},
        # Cathedral (305)
        {"uiMapID": 305, "wx": 1159.0, "wy": 1347.0, "kind": "boss", "title": "high inquisitor fairbanks", "subtitle": "secret chapel chamber (boss)"},
        {"uiMapID": 305, "wx": 1196.0, "wy": 1399.0, "kind": "boss", "title": "scarlet commander mograine", "subtitle": "crusader's chapel altar (boss)"},
        {"uiMapID": 305, "wx": 1212.0, "wy": 1399.0, "kind": "boss", "title": "high inquisitor whitemane", "subtitle": "crusader's chapel sanctum (boss)"},
    ]

    return {"instanceID": 189, "name": "scarlet monastery", "wings": wings_meta, "pins": sm_pins}, previews


CURATED_WMO_CAVES = {
    110650: ("shadow_grave", "shadow grave", None, 0, (1620.0, 1705.0, 1640.0, 1715.0), True),
    111538: ("spider_mine", "spider mine (deathknell)", None, 0, (1270.0, 1480.0, 1900.0, 2040.0), True),
    110602: ("agamand_crypt", "agamand family crypt", None, 0, (3000.0, 3090.0, 625.0, 720.0), True),
    111551: ("night_webs_hollow", "night web's hollow", 466, 0, (1980.0, 2120.0, 1810.0, 2010.0), True),
    107218: ("scarlet_monastery_ent", "scarlet monastery entrance", 19, 0, (2810.0, 2955.0, -875.0, -655.0), True),
}


def _clean_caveminimap_label(comment: str) -> str:
    raw = comment.split(",", 1)[0].strip()
    if re.fullmatch(r"\d+", raw):
        return f"forever cave {raw}"
    lbl = re.sub(r"^(?:md|kz|az|nd)_", "", raw.lower()).replace("_", " ").strip()
    return lbl or "cave"


def build_caves(
    casc: LocalCASC,
    maid_azeroth: bytes,
    caves_lua_txt: str,
    tile_px: int = TILE_PX,
    tile_jobs: list[tuple[Path, np.ndarray]] | None = None,
    *,
    poc_only: bool = False,
    cave_minimap_txt: str = "",
) -> tuple[list[dict[str, object]], dict[object, object]]:
    """Build 3D WMO crypts, Blizzard Caves.lua micro-maps, and OpenMap CaveMinimap.lua open-world interiors."""
    caves_out: list[dict[str, object]] = []
    cave_previews: dict[object, object] = {}
    stage2_boxes: list[tuple[int, float, float, float, float]] = []
    ss = SS_FACTOR
    hi_tile = tile_px * ss

    # 1. Scan Tirisfal ADTs for curated 3D WMO caves/crypts/vestibule
    matched_wmos: dict[int, tuple[float, float, float, float, float]] = {}
    for ty in range(25, 31):
        for tx in range(27, 35):
            ob_fid = struct.unpack_from("<I", maid_azeroth, (ty * 64 + tx) * 32 + 4)[0]
            if not ob_fid or ob_fid not in casc.fid_to_ckey:
                continue
            ob = casc.read_fid(ob_fid)
            p = 0
            while p + 8 <= len(ob):
                t = ob[p : p + 4][::-1]
                sz = struct.unpack_from("<I", ob, p + 4)[0]
                if t == b"MODF":
                    for k in range(0, sz, 64):
                        wf, _uid, px, py, pz, _rx, ry, _rz, _lx, _ly, _lz, _ux, _uy, _uz, flg, _did, _ns, sc = struct.unpack_from(
                            "<II12fHHHH", ob, p + 8 + k
                        )
                        if wf in CURATED_WMO_CAVES and wf not in matched_wmos:
                            wx, wy = 17066.6666667 - pz, 17066.6666667 - px
                            bx0, bx1, by0, by1 = CURATED_WMO_CAVES[wf][4]
                            if bx0 - 150 <= wx <= bx1 + 150 and by0 - 150 <= wy <= by1 + 150:
                                scale = (sc / 1024.0) if ((flg & 4) and sc > 0) else 1.0
                                matched_wmos[wf] = (px, py, pz, ry, scale)
                p += 8 + sz

    caves_bounds: dict[int, tuple[float, float, float, float]] = {}
    for mid in (466, 19):
        matches = [l for l in caves_lua_txt.splitlines() if f"[{mid}] =" in l]
        if matches:
            nums = re.findall(r"(-?\d+\.\d+|-?\d+)", matches[0])
            caves_bounds[mid] = (float(nums[2]), float(nums[4]), float(nums[3]), float(nums[5]))

    curated_map_ids: set[int] = set()
    for wfid, (cid, label, uimap_id, cont, fallback_box, indoor_only) in CURATED_WMO_CAVES.items():
        if wfid not in matched_wmos:
            raise RuntimeError(f"Missing cave WMO {wfid} ({cid}) in Tirisfal MODF")
        px, py, pz, ry, scale = matched_wmos[wfid]
        v, tris, nz, _fl, mat, is_in = extract_wmo_world_tris(
            casc, wfid, px, py, pz, ry, scale, indoor_only=indoor_only
        )
        rendered = (mat != 0xFF) & (mat != 0xFFFF)
        walk_t = rendered & (nz >= 0.50)
        wt = tris[walk_t]
        b_minx, b_maxx = float(v[wt][:, :, 0].min()), float(v[wt][:, :, 0].max())
        b_miny, b_maxy = float(v[wt][:, :, 1].min()), float(v[wt][:, :, 1].max())
        if uimap_id in caves_bounds:
            curated_map_ids.add(uimap_id)
            c0, c1, cy0, cy1 = caves_bounds[uimap_id]
            trig_minx, trig_maxx = min(c0, b_minx) - 4.0, max(c1, b_maxx) + 4.0
            trig_miny, trig_maxy = min(cy0, b_miny) - 4.0, max(cy1, b_maxy) + 4.0
        else:
            trig_minx, trig_maxx = b_minx - 8.0, b_maxx + 8.0
            trig_miny, trig_maxy = b_miny - 8.0, b_maxy + 8.0

        cx = (b_minx + b_maxx) * 0.5
        cy = (b_miny + b_maxy) * 0.5
        span = max(b_maxx - b_minx, b_maxy - b_miny) + 48.0
        span = float(math.ceil(span / 16.0) * 16.0)
        wx_max, wx_min = cx + span * 0.5, cx - span * 0.5
        wy_max, wy_min = cy + span * 0.5, cy - span * 0.5
        px_per_yard = hi_tile / span

        walkable, interior_lines = build_wmo_floorplan_masks(
            v, tris, nz, mat, is_in,
            wx_max, wy_max, hi_tile, hi_tile, px_per_yard,
            indoor_only=indoor_only, slice_h=1.25,
        )
        rgba = render_architectural_map(
            walkable,
            interior_lines=interior_lines,
            canal_mask=None,
            downsample=ss,
            max_hatch_dist=140.0,
            wall_thickness=3,
            halo_thickness=6,
            island_max_area=9000,
        )
        fname = f"cave_{cid}.blp"
        if tile_jobs is not None:
            tile_jobs.append((MEDIA_OUT / fname, np.array(rgba, copy=True)))
        else:
            save_blp2_dxt5(MEDIA_OUT / fname, rgba)
        caves_out.append(
            {
                "id": cid,
                "name": label,
                "cont": cont,
                "uiMapID": uimap_id,
                "minX": trig_minx,
                "maxX": trig_maxx,
                "minY": trig_miny,
                "maxY": trig_maxy,
                "texMinX": wx_min,
                "texMaxX": wx_max,
                "texMinY": wy_min,
                "texMaxY": wy_max,
                "tex": fname,
            }
        )
        if uimap_id is not None:
            cave_previews[uimap_id] = rgba

    if poc_only:
        return caves_out, cave_previews

    # 2. All remaining Blizzard cave micro-maps from OpenMap/Data/Forever/Caves.lua
    mc_dir = ADDONS_DIR / "OpenMap/Media/Textures/Forever/MapCave"
    pat = re.compile(
        r'^\s*\[(\d+)\]\s*=\s*\{\s*"([^"]+)",\s*(\d+),\s*'
        r'(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?),\s*'
        r'(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?),[^\{]+\{([^\}]+)\}',
        re.M,
    )
    for m in pat.finditer(caves_lua_txt):
        uimap_id = int(m.group(1))
        if uimap_id in curated_map_ids:
            continue
        label = m.group(2).lower()
        cont = int(m.group(3))
        min_x, min_y = float(m.group(4)), float(m.group(5))
        max_x, max_y = float(m.group(6)), float(m.group(7))
        fids = [int(x) for x in re.findall(r"\d+", m.group(8))]
        if len(fids) < 12 or not (mc_dir / f"{uimap_id}.tga").exists():
            continue

        # Stitch 1002x668 RGB image from the 12 BLP pieces (matching OpenMap Close.lua)
        stitched = np.zeros((668, 1002, 4), dtype=np.uint8)
        for n, fid in enumerate(fids[:12]):
            col_i, row_i = n % 4, n // 4
            pw = min(256, 1002 - col_i * 256)
            ph = min(256, 668 - row_i * 256)
            tile_arr = np.array(casc.read_blp_rgba(fid))
            stitched[row_i * 256 : row_i * 256 + ph, col_i * 256 : col_i * 256 + pw] = tile_arr[:ph, :pw]

        mask_tga = np.array(Image.open(mc_dir / f"{uimap_id}.tga").convert("RGBA"))
        mask_alpha = mask_tga[:, :, 3].astype(np.float32) / 255.0

        w_yd = max_y - min_y
        h_yd = max_x - min_x
        if w_yd <= 1.0 or h_yd <= 1.0:
            continue

        raw_span = max(w_yd, h_yd) + 40.0
        if max(w_yd, h_yd) <= 340.0:
            n_grid = 1
            step = float(math.ceil(raw_span / 16.0) * 16.0)
        else:
            n_grid = 2
            step = float(math.ceil((raw_span * 0.5) / 16.0) * 16.0)

        total_span = n_grid * step
        out_px = n_grid * tile_px
        hi_sz = out_px * ss
        px_per_yd = hi_sz / total_span

        cx = (min_x + max_x) * 0.5
        cy = (min_y + max_y) * 0.5
        gx_max, gx_min = cx + total_span * 0.5, cx - total_span * 0.5
        gy_max, gy_min = cy + total_span * 0.5, cy - total_span * 0.5

        rw = max(8, int(round(w_yd * px_per_yd)))
        rh = max(8, int(round(h_yd * px_per_yd)))
        x0 = (hi_sz - rw) // 2
        y0 = (hi_sz - rh) // 2

        mask_hi = cv2.resize(mask_alpha, (rw, rh), interpolation=cv2.INTER_CUBIC) >= 0.45
        mask_hi = remove_small_components(mask_hi, 24)
        walkable = np.zeros((hi_sz, hi_sz), dtype=bool)
        walkable[y0 : y0 + rh, x0 : x0 + rw] = mask_hi

        # Subtle interior rock/pillar line extraction from stitched BLP luminance
        rgb_hi = cv2.resize(stitched[:, :, :3].astype(np.float32), (rw, rh), interpolation=cv2.INTER_LINEAR)
        lum = 0.299 * rgb_hi[:, :, 0] + 0.587 * rgb_hi[:, :, 1] + 0.114 * rgb_hi[:, :, 2]
        eroded = cv2.erode(mask_hi.astype(np.uint8), np.ones((5, 5), dtype=np.uint8)) > 0
        int_rect = np.zeros((rh, rw), dtype=np.float32)
        if eroded.any():
            local_base = cv2.GaussianBlur(lum, (0, 0), sigmaX=7.0)
            dark_diff = np.clip((local_base - lum - 8.0) / 36.0, 0.0, 1.0)
            int_rect = dark_diff * eroded.astype(np.float32) * 0.55

        interior_lines = np.zeros((hi_sz, hi_sz), dtype=np.float32)
        interior_lines[y0 : y0 + rh, x0 : x0 + rw] = int_rect

        rgba = render_architectural_map(
            walkable,
            interior_lines=interior_lines,
            canal_mask=None,
            downsample=ss,
            max_hatch_dist=140.0,
            wall_thickness=3,
            halo_thickness=6,
            island_max_area=9000,
        )

        if n_grid == 1:
            fname = f"cave_m{uimap_id}.blp"
            if tile_jobs is not None:
                tile_jobs.append((MEDIA_OUT / fname, np.array(rgba, copy=True)))
            else:
                save_blp2_dxt5(MEDIA_OUT / fname, rgba)
            caves_out.append(
                {
                    "id": f"m{uimap_id}",
                    "name": label,
                    "cont": cont,
                    "uiMapID": uimap_id,
                    "minX": min_x,
                    "maxX": max_x,
                    "minY": min_y,
                    "maxY": max_y,
                    "texMinX": gx_min,
                    "texMaxX": gx_max,
                    "texMinY": gy_min,
                    "texMaxY": gy_max,
                    "tex": fname,
                }
            )
        else:
            tiles_map: dict[tuple[int, int], str] = {}
            for row_i in range(n_grid):
                for col_i in range(n_grid):
                    sub = rgba[row_i * tile_px : (row_i + 1) * tile_px, col_i * tile_px : (col_i + 1) * tile_px]
                    if sub[:, :, 3].max() > 0:
                        fname = f"cave_m{uimap_id}_{col_i}_{row_i}.blp"
                        if tile_jobs is not None:
                            tile_jobs.append((MEDIA_OUT / fname, np.array(sub, copy=True)))
                        else:
                            save_blp2_dxt5(MEDIA_OUT / fname, sub)
                        tiles_map[(col_i, row_i)] = fname
            caves_out.append(
                {
                    "id": f"m{uimap_id}",
                    "name": label,
                    "cont": cont,
                    "uiMapID": uimap_id,
                    "minX": min_x,
                    "maxX": max_x,
                    "minY": min_y,
                    "maxY": max_y,
                    "gridMaxX": gx_max,
                    "gridMaxY": gy_max,
                    "cols": n_grid,
                    "rows": n_grid,
                    "stepYards": step,
                    "tiles": tiles_map,
                }
            )

        if uimap_id in (33, 55, 11):
            cave_previews[uimap_id] = rgba
        stage2_boxes.append((cont, min_x, max_x, min_y, max_y))

    # 3. All unmapped open-world WMO caves, tunnels, hives & Forever caves from CaveMinimap.lua
    cm_added = 0
    cm_skipped = 0
    if cave_minimap_txt:
        cm_pat = re.compile(
            r"^\t\{\s*(\d+),\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*\{([^}]+)\}\s*\},?\s*--\s*(.+)$",
            re.M,
        )
        curated_boxes = [(v[3], v[4][0], v[4][1], v[4][2], v[4][3]) for v in CURATED_WMO_CAVES.values()]
        blp_cache: dict[tuple[int, bool], np.ndarray] = {}

        for m in cm_pat.finditer(cave_minimap_txt):
            cont = int(m.group(1))
            min_x, min_y = float(m.group(2)), float(m.group(3))
            max_x, max_y = float(m.group(4)), float(m.group(5))
            pics_str = m.group(6)
            cmt = m.group(7).strip()

            cx = (min_x + max_x) * 0.5
            cy = (min_y + max_y) * 0.5
            if any(
                bc == cont and (bx0 - 20.0) <= cx <= (bx1 + 20.0) and (by0 - 20.0) <= cy <= (by1 + 20.0)
                for bc, bx0, bx1, by0, by1 in curated_boxes
            ):
                cm_skipped += 1
                continue
            if any(
                bc == cont and bx0 <= cx <= bx1 and by0 <= cy <= by1
                for bc, bx0, bx1, by0, by1 in stage2_boxes
            ):
                cm_skipped += 1
                continue

            pieces = parse_wmo_pieces_string(pics_str)
            if not pieces:
                continue

            w_yd = max_y - min_y
            h_yd = max_x - min_x
            max_dim = max(w_yd, h_yd)
            if max_dim <= 1.0:
                continue

            raw_span = max_dim + 40.0
            if max_dim <= 140.0:
                n_grid = 1
                out_tile_px = 256
                step = float(math.ceil(raw_span / 16.0) * 16.0)
                wall_t, halo_t, max_hatch, island_max = 2, 4, 96.0, 2500
            elif max_dim <= 360.0:
                n_grid = 1
                out_tile_px = tile_px
                step = float(math.ceil(raw_span / 16.0) * 16.0)
                wall_t, halo_t, max_hatch, island_max = 3, 6, 140.0, 9000
            elif max_dim <= 720.0:
                n_grid = 2
                out_tile_px = tile_px
                step = float(math.ceil((raw_span * 0.5) / 16.0) * 16.0)
                wall_t, halo_t, max_hatch, island_max = 3, 6, 140.0, 9000
            else:
                n_grid = 3
                out_tile_px = tile_px
                step = float(math.ceil((raw_span / 3.0) / 16.0) * 16.0)
                wall_t, halo_t, max_hatch, island_max = 3, 6, 140.0, 9000

            total_span = n_grid * step
            hi_sz = n_grid * out_tile_px * ss
            px_per_yd = hi_sz / total_span
            gx_max, gx_min = cx + total_span * 0.5, cx - total_span * 0.5
            gy_max, gy_min = cy + total_span * 0.5, cy - total_span * 0.5

            comp_im = composite_wmo_pieces(
                casc, pieces, gx_max, gy_max, hi_sz, hi_sz, px_per_yd, blp_cache=blp_cache
            )
            arr = np.array(comp_im)
            walkable = (
                cv2.morphologyEx(
                    (arr[:, :, 3] > 26).astype(np.uint8),
                    cv2.MORPH_CLOSE,
                    np.ones((3, 3), dtype=np.uint8),
                )
                > 0
            )
            walkable = remove_small_components(walkable, 24)
            if not walkable.any():
                continue

            rgb_f = arr[:, :, :3].astype(np.float32)
            lum = 0.299 * rgb_f[:, :, 0] + 0.587 * rgb_f[:, :, 1] + 0.114 * rgb_f[:, :, 2]
            eroded = cv2.erode(walkable.astype(np.uint8), np.ones((5, 5), dtype=np.uint8)) > 0
            interior_lines = np.zeros((hi_sz, hi_sz), dtype=np.float32)
            if eroded.any():
                local_base = cv2.GaussianBlur(lum, (0, 0), sigmaX=7.0)
                dark_diff = np.clip((local_base - lum - 8.0) / 36.0, 0.0, 1.0)
                interior_lines = dark_diff * eroded.astype(np.float32) * 0.55

            rgba = render_architectural_map(
                walkable,
                interior_lines=interior_lines,
                canal_mask=None,
                downsample=ss,
                max_hatch_dist=max_hatch,
                wall_thickness=wall_t,
                halo_thickness=halo_t,
                island_max_area=island_max,
            )

            cm_added += 1
            cid = f"cm{cm_added}"
            label = _clean_caveminimap_label(cmt)
            trig_minx, trig_maxx = min_x - 6.0, max_x + 6.0
            trig_miny, trig_maxy = min_y - 6.0, max_y + 6.0

            if n_grid == 1:
                fname = f"cave_{cid}.blp"
                if tile_jobs is not None:
                    tile_jobs.append((MEDIA_OUT / fname, np.array(rgba, copy=True)))
                else:
                    save_blp2_dxt5(MEDIA_OUT / fname, rgba)
                entry: dict[str, object] = {
                    "id": cid,
                    "name": label,
                    "cont": cont,
                    "uiMapID": None,
                    "minX": trig_minx,
                    "maxX": trig_maxx,
                    "minY": trig_miny,
                    "maxY": trig_maxy,
                    "texMinX": gx_min,
                    "texMaxX": gx_max,
                    "texMinY": gy_min,
                    "texMaxY": gy_max,
                    "tex": fname,
                }
            else:
                tiles_map: dict[tuple[int, int], str] = {}
                for row_i in range(n_grid):
                    for col_i in range(n_grid):
                        sub = rgba[
                            row_i * out_tile_px : (row_i + 1) * out_tile_px,
                            col_i * out_tile_px : (col_i + 1) * out_tile_px,
                        ]
                        if sub[:, :, 3].max() > 0:
                            fname = f"cave_{cid}_{col_i}_{row_i}.blp"
                            if tile_jobs is not None:
                                tile_jobs.append((MEDIA_OUT / fname, np.array(sub, copy=True)))
                            else:
                                save_blp2_dxt5(MEDIA_OUT / fname, sub)
                            tiles_map[(col_i, row_i)] = fname
                entry = {
                    "id": cid,
                    "name": label,
                    "cont": cont,
                    "uiMapID": None,
                    "minX": trig_minx,
                    "maxX": trig_maxx,
                    "minY": trig_miny,
                    "maxY": trig_maxy,
                    "gridMaxX": gx_max,
                    "gridMaxY": gy_max,
                    "cols": n_grid,
                    "rows": n_grid,
                    "stepYards": step,
                    "tiles": tiles_map,
                }

            caves_out.append(entry)
            if "md_timbermawhold" in cmt:
                cave_previews["timbermaw"] = (entry, rgba, cmt)
            elif "kz_gnomeragon" in cmt:
                cave_previews["gnomeregan_ent"] = (entry, rgba, cmt)
            elif cmt == "21067":
                cave_previews["forever_21067"] = (entry, rgba, cmt)

    print(
        f"Built {len(caves_out)} cave/crypt/pre-instance entries "
        f"(3D WMO + Caves.lua + {cm_added} CaveMinimap.lua; skipped {cm_skipped} overlaps)"
    )
    return caves_out, cave_previews


def decode_cbor(data: bytes):
    pos = 0

    def read():
        nonlocal pos
        b = data[pos]
        pos += 1
        major, add = b >> 5, b & 0x1F

        def r_uint(a: int) -> int:
            nonlocal pos
            if a < 24:
                return a
            if a == 24:
                v = data[pos]
                pos += 1
                return v
            if a == 25:
                v = struct.unpack_from(">H", data, pos)[0]
                pos += 2
                return v
            if a == 26:
                v = struct.unpack_from(">I", data, pos)[0]
                pos += 4
                return v
            if a == 27:
                v = struct.unpack_from(">Q", data, pos)[0]
                pos += 8
                return v
            raise ValueError(f"Unsupported CBOR uint add={a}")

        if major == 0:
            return r_uint(add)
        if major == 1:
            return -1 - r_uint(add)
        if major == 2:
            n = r_uint(add)
            v = data[pos : pos + n]
            pos += n
            return v
        if major == 3:
            n = r_uint(add)
            v = data[pos : pos + n].decode("utf-8", "replace")
            pos += n
            return v
        if major == 4:
            if add == 31:
                out = []
                while data[pos] != 0xFF:
                    out.append(read())
                pos += 1
                return out
            return [read() for _ in range(r_uint(add))]
        if major == 5:
            if add == 31:
                out = {}
                while data[pos] != 0xFF:
                    k = read()
                    out[k] = read()
                pos += 1
                return out
            return {read(): read() for _ in range(r_uint(add))}
        if major == 6:
            _ = r_uint(add)
            return read()
        if major == 7:
            if add == 20:
                return False
            if add == 21:
                return True
            if add in (22, 23):
                return None
            if add == 24:
                v = data[pos]
                pos += 1
                return v
            if add == 25:
                v = struct.unpack_from(">e", data, pos)[0]
                pos += 2
                return v
            if add == 26:
                v = struct.unpack_from(">f", data, pos)[0]
                pos += 4
                return v
            if add == 27:
                v = struct.unpack_from(">d", data, pos)[0]
                pos += 8
                return v
        raise ValueError(f"Unsupported CBOR major={major} add={add}")

    return read()


def index_questiedb_poc() -> dict[str, object]:
    """Parse QuestieDB_Forever.toc CBOR rows for Tirisfal Glades (85) & Undercity (1497)."""
    sub_path = ADDONS_DIR / "QuestieDB/support/Forever/Zones/subZoneToParentZone.lua"
    sub_txt = sub_path.read_text(encoding="utf-8")
    area_to_parent: dict[int, int] = {}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", sub_txt):
        area_to_parent[int(m.group(1))] = int(m.group(2))

    # Build transitive subzone -> root PoC area mapping (85 -> 1420, 1497 -> 1458)
    poc_area_to_uimap: dict[int, int] = {85: 1420, 1497: 1458}
    for sub_id in list(area_to_parent.keys()):
        cur = sub_id
        for _ in range(5):
            if cur in (85, 1497):
                poc_area_to_uimap[sub_id] = 1420 if cur == 85 else 1458
                break
            nxt = area_to_parent.get(cur)
            if not nxt or nxt == cur:
                break
            cur = nxt

    toc_path = ADDONS_DIR / "QuestieDB/QuestieDB_Forever.toc"
    raw_meta: dict[str, str] = {}
    with open(toc_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith("## X-"):
                continue
            k, _, v = line[3:].partition(":")
            key = k.strip()
            if key.startswith(("X-Npc-", "X-Object-")):
                raw_meta[key] = v.strip()

    def get_stored(key: str) -> str | None:
        v = raw_meta.get(key)
        if not v:
            return None
        if v.startswith("~"):
            m = re.match(r"^~(\d+)~$", v)
            if m:
                cnt = int(m.group(1))
                return "".join(raw_meta[f"{key}-{i}"] for i in range(1, cnt + 1))
        return v

    # Collect all NPC and Object IDs from their spawn metadata keys (strict numeric ID match)
    npc_ids = sorted(
        {
            int(m.group(1))
            for k in raw_meta
            for m in (re.match(r"^X-Npc-(\d+)-7$", k),)
            if m
        }
    )
    obj_ids = sorted(
        {
            int(m.group(1))
            for k in raw_meta
            for m in (re.match(r"^X-Object-(\d+)-4$", k),)
            if m
        }
    )

    # Townsfolk flags from npcMeta / Constants: repair=4096, flightmaster=8192, innkeeper=65536, banker=131072, auctioneer=2097152, battlemaster=1048576
    TOWNSFOLK_MASK = 4096 | 8192 | 65536 | 131072 | 1048576 | 2097152

    zone_npcs: dict[int, list[int]] = {1420: [], 1458: []}
    preview_pins: list[dict[str, object]] = []

    for nid in npc_ids:
        sp_b64 = get_stored(f"X-Npc-{nid}-7")
        if not sp_b64:
            continue
        spawns = decode_cbor(base64.b64decode(sp_b64))
        if not isinstance(spawns, dict):
            continue
        matched_maps = {
            poc_area_to_uimap[int(z)] for z in spawns if int(z) in poc_area_to_uimap
        }
        if not matched_maps:
            continue
        s_b64 = get_stored(f"X-Npc-{nid}-S")
        s_row = decode_cbor(base64.b64decode(s_b64)) if s_b64 else {}
        pmask = s_row.get(b"p", 0) if isinstance(s_row, dict) else 0
        has_starts = bool(pmask & (1 << (10 - 1)))
        has_ends = bool(pmask & (1 << (11 - 1)))
        npc_flags = s_row.get(15, 0) if isinstance(s_row, dict) else 0
        is_town = bool(npc_flags & TOWNSFOLK_MASK)
        if not (has_starts or has_ends or is_town):
            continue

        # Exclude Alliance-only or pure non-interactive if needed, keep all valid Horde/Neutral quest/townsfolk for preview
        friendly = s_row.get(13, b"")
        if isinstance(friendly, bytes):
            friendly = friendly.decode("utf-8", "ignore")
        name_raw = s_row.get(1, b"")
        name = name_raw.decode("utf-8", "ignore") if isinstance(name_raw, bytes) else str(name_raw)

        for uimap in matched_maps:
            zone_npcs[uimap].append(nid)

        if has_starts:
            kind = "quest_start"
        elif has_ends:
            kind = "quest_end"
        else:
            kind = "townsfolk"

        for z, coords in spawns.items():
            zi = int(z)
            if zi in poc_area_to_uimap and isinstance(coords, list):
                um = poc_area_to_uimap[zi]
                for pt in coords:
                    if isinstance(pt, list) and len(pt) >= 2:
                        preview_pins.append(
                            {
                                "uiMapID": um,
                                "x": float(pt[0]),
                                "y": float(pt[1]),
                                "kind": kind,
                                "name": name,
                                "id": nid,
                                "friendly": friendly,
                                "flags": int(npc_flags),
                            }
                        )

    zone_objs: dict[int, list[int]] = {1420: [], 1458: []}
    for oid in obj_ids:
        sp_b64 = get_stored(f"X-Object-{oid}-4")
        if not sp_b64:
            continue
        spawns = decode_cbor(base64.b64decode(sp_b64))
        if not isinstance(spawns, dict):
            continue
        matched_maps = {
            poc_area_to_uimap[int(z)] for z in spawns if int(z) in poc_area_to_uimap
        }
        if not matched_maps:
            continue
        s_b64 = get_stored(f"X-Object-{oid}-S")
        s_row = decode_cbor(base64.b64decode(s_b64)) if s_b64 else {}
        pmask = s_row.get(b"p", 0) if isinstance(s_row, dict) else 0
        has_q = bool(pmask & ((1 << (2 - 1)) | (1 << (3 - 1))))
        if not has_q:
            continue
        for uimap in matched_maps:
            zone_objs[uimap].append(oid)
        name_raw = s_row.get(1, b"")
        name = name_raw.decode("utf-8", "ignore") if isinstance(name_raw, bytes) else str(name_raw)
        kind = "quest_start" if (pmask & (1 << (2 - 1))) else "quest_end"
        for z, coords in spawns.items():
            zi = int(z)
            if zi in poc_area_to_uimap and isinstance(coords, list):
                um = poc_area_to_uimap[zi]
                for pt in coords:
                    if isinstance(pt, list) and len(pt) >= 2:
                        preview_pins.append(
                            {
                                "uiMapID": um,
                                "x": float(pt[0]),
                                "y": float(pt[1]),
                                "kind": kind,
                                "name": name,
                                "id": -oid,
                                "friendly": "H",
                                "flags": 0,
                            }
                        )

    print(
        f"QuestieDB indexed PoC: Tirisfal NPCs={len(zone_npcs[1420])}, "
        f"Undercity NPCs={len(zone_npcs[1458])}, Tirisfal Objects={len(zone_objs[1420])}, "
        f"Undercity Objects={len(zone_objs[1458])}"
    )
    return {
        "subZoneToUiMapId": poc_area_to_uimap,
        "zoneNpcs": zone_npcs,
        "zoneObjects": zone_objs,
        "previewPins": preview_pins,
    }


def load_forever_area_map() -> dict[int, int]:
    """Load all Forever areaId -> uiMapID mappings from QuestieDB support zone tables."""
    zdir = ADDONS_DIR / "QuestieDB/support/Forever/Zones"
    amap = {
        int(k): int(v)
        for k, v in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", (zdir / "areaIdToUiMapId.lua").read_text(encoding="utf-8"))
    }
    pmap = {
        int(k): int(v)
        for k, v in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", (zdir / "subZoneToParentZone.lua").read_text(encoding="utf-8"))
    }
    resolved = {k: v for k, v in amap.items() if v > 0}
    for sub in pmap:
        if sub in resolved:
            continue
        cur = sub
        for _ in range(8):
            if cur in amap:
                if amap[cur] > 0:
                    resolved[sub] = amap[cur]
                break
            nxt = pmap.get(cur)
            if not nxt or nxt == cur:
                break
            cur = nxt
    print(f"QuestieDB Forever area map: {len(resolved)} resolved areaId -> uiMapID entries")
    return resolved


def _load_existing_continents_and_cities(
    lua_path: Path,
) -> tuple[dict[int, dict[tuple[int, int], object]], dict[int, dict[str, object]]]:
    """Parse preserved `continents` and `cities` tables from existing overlay_maps_camelot.lua."""
    if not lua_path.exists():
        raise RuntimeError(f"Cannot run --caves-only: missing existing manifest {lua_path}")
    src = lua_path.read_text(encoding="utf-8")
    cont_block = src[src.index("continents = {") : src.index("cities = {")]
    continents: dict[int, dict[tuple[int, int], object]] = {}
    for cid in (0, 1):
        m = re.search(rf"^\s+\[{cid}\]\s*=\s*\{{(.*?)\n\s{{8}}\}},", cont_block, re.S | re.M)
        if not m:
            continue
        tiles: dict[tuple[int, int], object] = {}
        for km in re.finditer(r"\[(\d+)\]\s*=\s*(true|\"[^\"]+\")", m.group(1)):
            idx = int(km.group(1))
            val: object = True if km.group(2) == "true" else km.group(2).strip('"')
            tiles[(idx // 64, idx % 64)] = val
        continents[cid] = tiles

    cities_block = src[src.index("cities = {") : src.index("instances = {")]
    cities: dict[int, dict[str, object]] = {}
    for cm in re.finditer(r"^\s+\[(\d+)\]\s*=\s*\{(.*?)\n\s{8}\},", cities_block, re.S | re.M):
        mid = int(cm.group(1))
        body = cm.group(2)
        cont_m = re.search(r"\bcont\s*=\s*(\d+)", body)
        name_m = re.search(r'\bname\s*=\s*"([^"]+)"', body)
        maxx_m = re.search(r"\bmaxX\s*=\s*(-?[\d.]+)", body)
        minx_m = re.search(r"\bminX\s*=\s*(-?[\d.]+)", body)
        maxy_m = re.search(r"\bmaxY\s*=\s*(-?[\d.]+)", body)
        miny_m = re.search(r"\bminY\s*=\s*(-?[\d.]+)", body)
        cols_m = re.search(r"\bcols\s*=\s*(\d+)", body)
        rows_m = re.search(r"\brows\s*=\s*(\d+)", body)
        step_m = re.search(r"\bstepYards\s*=\s*(-?[\d.]+)", body)
        assert cont_m and name_m and maxx_m and minx_m and maxy_m and miny_m and cols_m and rows_m and step_m, (
            f"Incomplete city block [{mid}] in {lua_path}"
        )
        tiles_section = body[body.index("tiles = {") :]
        ctiles: dict[tuple[int, int], str] = {}
        for tm in re.finditer(r'\[(\d+)\]\s*=\s*"([^"]+)"', tiles_section):
            idx = int(tm.group(1))
            ctiles[(idx // 16, idx % 16)] = tm.group(2)
        cities[mid] = {
            "uiMapID": mid,
            "cont": int(cont_m.group(1)),
            "name": name_m.group(1),
            "maxX": float(maxx_m.group(1)),
            "minX": float(minx_m.group(1)),
            "maxY": float(maxy_m.group(1)),
            "minY": float(miny_m.group(1)),
            "cols": int(cols_m.group(1)),
            "rows": int(rows_m.group(1)),
            "stepYards": float(step_m.group(1)),
            "tiles": ctiles,
        }
    assert len(continents.get(0, {})) > 0 and len(continents.get(1, {})) > 0, "Missing continent tiles in manifest"
    assert set(cities.keys()) == {1455, 1458}, f"Unexpected preserved cities: {sorted(cities.keys())}"
    return continents, cities


def write_lua_manifest(
    continents: dict[int, dict[tuple[int, int], object]],
    cities: dict[int, dict[str, object]],
    caves: list[dict[str, object]],
    sm_meta: dict[str, object] | None,
    vestibule_pins: list[dict[str, object]],
    subzone_map: dict[int, int],
) -> None:
    lines = [
        "local _, _ = ...",
        "sfui = sfui or {}",
        "",
        "if sfui.isRetail then return end",
        "",
        "-- generated by scripts/generate_overlay_poc.py (blp2 dxt5 architectural contours)",
        "sfui.overlay_maps_data = {",
        '    texBase = "Interface\\\\AddOns\\\\sfui_overlay_maps\\\\media\\\\",',
        f"    tileYards = {TILE_YARDS:.10f},",
        '    continentPrefixes = { [0] = "ek", [1] = "kal" },',
        "    continents = {",
    ]
    for cont_id in sorted(continents):
        lines.append(f"        [{cont_id}] = {{")
        for (tx, ty) in sorted(continents[cont_id].keys()):
            lines.append(f"            [{tx * 64 + ty}] = true,")
        lines.append("        },")
    lines.extend(["    },", "    cities = {"])
    for mid, cmeta in sorted(cities.items()):
        lines.extend(
            [
                f"        [{mid}] = {{",
                f"            uiMapID = {mid},",
                f"            cont = {int(cmeta.get('cont', 0))},",
                f'            name = "{str(cmeta["name"]).lower()}",',
                f"            maxX = {cmeta['maxX']:.3f},",
                f"            minX = {cmeta['minX']:.3f},",
                f"            maxY = {cmeta['maxY']:.3f},",
                f"            minY = {cmeta['minY']:.3f},",
                f"            cols = {cmeta['cols']},",
                f"            rows = {cmeta['rows']},",
                f"            stepYards = {cmeta['stepYards']:.1f},",
                "            tiles = {",
            ]
        )
        ctiles: dict[tuple[int, int], str] = cmeta["tiles"]  # type: ignore[assignment]
        for (col, row), fname in sorted(ctiles.items()):
            lines.append(f'                [{col * 16 + row}] = "{fname}",')
        lines.extend(["            },", "        },"])
    lines.extend(["    },", "    instances = {"])
    if sm_meta is not None:
        lines.extend(
            [
                f"        [{sm_meta['instanceID']}] = {{",
                f'            name = "{str(sm_meta["name"]).lower()}",',
                "            wings = {",
            ]
        )
        for w in sm_meta["wings"]:  # type: ignore[union-attr]
            lines.extend(
                [
                    "                {",
                    f'                    id = "{w["id"]}",',
                    f'                    name = "{str(w["name"]).lower()}",',
                    f"                    uiMapID = {w['uiMapID']},",
                    f"                    minX = {w['minX']:.3f}, maxX = {w['maxX']:.3f},",
                    f"                    minY = {w['minY']:.3f}, maxY = {w['maxY']:.3f},",
                    f"                    gridMinX = {w['gridMinX']:.3f}, gridMaxX = {w['gridMaxX']:.3f},",
                    f"                    gridMinY = {w['gridMinY']:.3f}, gridMaxY = {w['gridMaxY']:.3f},",
                    f"                    cols = {w['cols']}, rows = {w['rows']},",
                    f"                    stepYards = {w['stepYards']:.1f},",
                    "                    tiles = {",
                ]
            )
            wtiles: dict[tuple[int, int], str] = w["tiles"]  # type: ignore[assignment]
            for (col, row), fname in sorted(wtiles.items()):
                lines.append(f'                        [{col * 64 + row}] = "{fname}",')
            lines.extend(["                    },", "                },"])
        lines.extend(["            },", "            pins = {"])
        for p in sm_meta["pins"]:  # type: ignore[union-attr]
            fac = f'"{p["faction"]}"' if "faction" in p else "nil"
            qid = str(p["questId"]) if "questId" in p else "nil"
            lines.append(
                f'                {{ uiMapID = {p["uiMapID"]}, wx = {p["wx"]:.2f}, wy = {p["wy"]:.2f}, '
                f'kind = "{p["kind"]}", title = "{str(p["title"]).lower()}", '
                f'subtitle = "{str(p["subtitle"]).lower()}", faction = {fac}, questId = {qid} }},'
            )
        lines.extend(["            },", "        },"])
    lines.extend(["    },", "    vestibulePins = {"])
    for vp in vestibule_pins:
        lines.append(
            f'        {{ wx = {vp["wx"]:.2f}, wy = {vp["wy"]:.2f}, kind = "{vp["kind"]}", '
            f'title = "{str(vp["title"]).lower()}", subtitle = "{str(vp["subtitle"]).lower()}" }},'
        )
    lines.extend(["    },", "    caves = {"])
    for c in caves:
        um = str(c["uiMapID"]) if c["uiMapID"] is not None else "nil"
        lines.extend(
            [
                "        {",
                f'            id = "{c["id"]}",',
                f'            name = "{str(c["name"]).lower()}",',
                f"            cont = {int(c.get('cont', 0))},",
                f"            uiMapID = {um},",
                f"            minX = {c['minX']:.3f}, maxX = {c['maxX']:.3f},",
                f"            minY = {c['minY']:.3f}, maxY = {c['maxY']:.3f},",
            ]
        )
        if "tiles" in c:
            lines.extend(
                [
                    f"            gridMaxX = {c['gridMaxX']:.3f}, gridMaxY = {c['gridMaxY']:.3f},",
                    f"            cols = {c['cols']}, rows = {c['rows']},",
                    f"            stepYards = {c['stepYards']:.1f},",
                    "            tiles = {",
                ]
            )
            ctiles_m: dict[tuple[int, int], str] = c["tiles"]  # type: ignore[assignment]
            for (col, row), fname in sorted(ctiles_m.items()):
                lines.append(f'                [{col * 16 + row}] = "{fname}",')
            lines.append("            },")
        else:
            lines.extend(
                [
                    f"            texMinX = {c['texMinX']:.3f}, texMaxX = {c['texMaxX']:.3f},",
                    f"            texMinY = {c['texMinY']:.3f}, texMaxY = {c['texMaxY']:.3f},",
                    f'            tex = "{c["tex"]}",',
                ]
            )
        lines.append("        },")
    lines.extend(["    },", "    subZoneToUiMapId = {"])
    for z, um in sorted(subzone_map.items()):
        lines.append(f"        [{z}] = {um},")
    lines.extend(["    },", "}", ""])
    DATA_OUT.parent.mkdir(parents=True, exist_ok=True)
    DATA_OUT.write_text("\n".join(lines), encoding="utf-8")


def _composite_world_view(
    overlay_rgba: np.ndarray,
    wx_max: float,
    wx_min: float,
    wy_max: float,
    wy_min: float,
    center_wx: float,
    center_wy: float,
    view_radius: float,
    out_sz: int,
    *,
    feather: bool = True,
) -> Image.Image:
    oh, ow = overlay_rgba.shape[:2]
    px_per_yd_x = ow / (wy_max - wy_min)
    px_per_yd_y = oh / (wx_max - wx_min)
    cx_px = (wy_max - center_wy) * px_per_yd_x
    cy_px = (wx_max - center_wx) * px_per_yd_y
    half_x = view_radius * px_per_yd_x
    half_y = view_radius * px_per_yd_y
    src_x0 = cx_px - half_x
    src_y0 = cy_px - half_y
    M = np.array(
        [
            [out_sz / (2.0 * half_x), 0.0, -src_x0 * out_sz / (2.0 * half_x)],
            [0.0, out_sz / (2.0 * half_y), -src_y0 * out_sz / (2.0 * half_y)],
        ],
        dtype=np.float32,
    )
    warped = cv2.warpAffine(overlay_rgba, M, (out_sz, out_sz), flags=cv2.INTER_LINEAR)
    if feather:
        yy, xx = np.mgrid[0:out_sz, 0:out_sz].astype(np.float32)
        r = np.sqrt((xx - out_sz * 0.5) ** 2 + (yy - out_sz * 0.5) ** 2) / (out_sz * 0.5)
        t = np.clip((r - 0.68) / (0.98 - 0.68), 0.0, 1.0)
        mask = 0.5 * (1.0 + np.cos(math.pi * t))
    else:
        mask = 1.0
    comp = np.full((out_sz, out_sz, 3), 24.0, dtype=np.float32)
    a = (warped[:, :, 3].astype(np.float32) / 255.0) * mask * 0.94
    for ch in range(3):
        comp[:, :, ch] = comp[:, :, ch] * (1.0 - a) + warped[:, :, ch].astype(np.float32) * a
    return Image.fromarray(np.clip(comp, 0, 255).astype(np.uint8), mode="RGB")


def render_preview(
    out_path: Path,
    overlay_rgba: np.ndarray,
    wx_max: float,
    wx_min: float,
    wy_max: float,
    wy_min: float,
    center_wx: float,
    center_wy: float,
    view_radius: float,
    pins: list[dict[str, object]],
    uimap_bounds: dict[int, tuple[float, float, float, float]],
    title: str,
) -> None:
    """Render a 900x900 dark-world ARPG overlay preview PNG with radial feather & pins."""
    out_sz = 900
    im = _composite_world_view(
        overlay_rgba, wx_max, wx_min, wy_max, wy_min,
        center_wx, center_wy, view_radius, out_sz, feather=True,
    )
    draw = ImageDraw.Draw(im, "RGBA")

    ppy = out_sz / (2.0 * view_radius)
    drawn = 0
    for p in pins:
        if "wx" in p and "wy" in p:
            pwx, pwy = float(p["wx"]), float(p["wy"])
        else:
            um = int(p["uiMapID"])
            if um not in uimap_bounds:
                continue
            left, right, top, bottom = uimap_bounds[um]
            pwx = top - (float(p["y"]) / 100.0) * (top - bottom)
            pwy = left - (float(p["x"]) / 100.0) * (left - right)
        dx = center_wy - pwy
        dy = center_wx - pwx
        if math.hypot(dx, dy) > view_radius * 0.92:
            continue
        sx = out_sz * 0.5 + dx * ppy
        sy = out_sz * 0.5 + dy * ppy
        kind = str(p["kind"])
        if kind == "quest_start":
            draw.ellipse([sx - 6, sy - 6, sx + 6, sy + 6], fill=(255, 210, 35, 240), outline=(25, 18, 8, 255), width=2)
            draw.text((sx - 2, sy - 6), "!", fill=(20, 14, 6, 255))
        elif kind == "quest_end":
            draw.ellipse([sx - 6, sy - 6, sx + 6, sy + 6], fill=(255, 210, 35, 240), outline=(25, 18, 8, 255), width=2)
            draw.text((sx - 3, sy - 6), "?", fill=(20, 14, 6, 255))
        elif kind == "boss":
            draw.ellipse([sx - 6, sy - 6, sx + 6, sy + 6], fill=(210, 56, 56, 240), outline=(255, 220, 170, 255), width=2)
            draw.text((sx - 3, sy - 6), "x", fill=(255, 240, 220, 255))
        else:
            draw.ellipse([sx - 5, sy - 5, sx + 5, sy + 5], fill=(102, 204, 255, 225), outline=(12, 20, 30, 255), width=2)
        drawn += 1

    c = out_sz * 0.5
    draw.polygon(
        [(c, c - 12), (c + 8, c + 10), (c, c + 5), (c - 8, c + 10)],
        fill=(245, 248, 255, 255),
        outline=(20, 22, 28, 255),
    )
    draw.text((16, 16), f"{title.lower()} (pins: {drawn})", fill=(220, 208, 185, 220))
    im.save(out_path, format="PNG")


def render_sm_showcase(
    out_path: Path,
    sm_meta: dict[str, object],
    sm_previews: dict[str, dict[str, object]],
) -> None:
    """Render a 900x900 2x2 Scarlet Monastery showcase (Graveyard, Library, Armory, Cathedral)."""
    panel_sz = 450
    sheet = Image.new("RGB", (900, 900), (24, 24, 24))
    centers = {
        "graveyard": (1750.0, 1210.0, 235.0, (0, 0)),
        "library": (205.0, -295.0, 185.0, (panel_sz, 0)),
        "armory": (1755.0, -355.0, 255.0, (0, panel_sz)),
        "cathedral": (1010.0, 1380.0, 245.0, (panel_sz, panel_sz)),
    }
    pins: list[dict[str, object]] = sm_meta["pins"]  # type: ignore[assignment]
    for w in sm_meta["wings"]:  # type: ignore[union-attr]
        sid = str(w["id"])
        pdat = sm_previews[sid]
        cwx, cwy, vrad, (ox, oy) = centers[sid]
        sub = _composite_world_view(
            pdat["rgba"],  # type: ignore[arg-type]
            float(pdat["maxX"]),  # type: ignore[arg-type]
            float(pdat["minX"]),  # type: ignore[arg-type]
            float(pdat["maxY"]),  # type: ignore[arg-type]
            float(pdat["minY"]),  # type: ignore[arg-type]
            cwx, cwy, vrad, panel_sz, feather=False,
        )
        draw = ImageDraw.Draw(sub, "RGBA")
        ppy = panel_sz / (2.0 * vrad)
        for p in pins:
            if int(p["uiMapID"]) != int(w["uiMapID"]):
                continue
            sx = panel_sz * 0.5 + (cwy - float(p["wy"])) * ppy
            sy = panel_sz * 0.5 + (cwx - float(p["wx"])) * ppy
            if str(p["kind"]) == "boss":
                draw.ellipse([sx - 5, sy - 5, sx + 5, sy + 5], fill=(215, 58, 58, 245), outline=(255, 224, 175, 255), width=2)
            else:
                draw.ellipse([sx - 5, sy - 5, sx + 5, sy + 5], fill=(255, 210, 35, 245), outline=(25, 18, 8, 255), width=2)
        draw.rectangle([0, 0, panel_sz - 1, panel_sz - 1], outline=(55, 55, 62, 220), width=1)
        draw.text((12, 10), str(w["name"]).lower(), fill=(224, 206, 170, 235))
        sheet.paste(sub, (ox, oy))
    sheet.save(out_path, format="PNG")


def _stitch_preview_tiles(
    tiles: dict[tuple[int, int], np.ndarray],
    tx0: int,
    tx1: int,
    ty0: int,
    ty1: int,
    tile_px: int = TILE_PX,
) -> tuple[np.ndarray, float, float, float, float]:
    """Stitch a rectangular subset of preview tiles into one RGBA canvas + world bounds."""
    nx = tx1 - tx0 + 1
    ny = ty1 - ty0 + 1
    canvas = np.zeros((ny * tile_px, nx * tile_px, 4), dtype=np.uint8)
    for yi, ty in enumerate(range(ty0, ty1 + 1)):
        for xi, tx in enumerate(range(tx0, tx1 + 1)):
            tile = tiles.get((tx, ty))
            if tile is not None:
                canvas[yi * tile_px : (yi + 1) * tile_px, xi * tile_px : (xi + 1) * tile_px] = tile
    wx_max = (32 - ty0) * TILE_YARDS
    wx_min = (31 - ty1) * TILE_YARDS
    wy_max = (32 - tx0) * TILE_YARDS
    wy_min = (31 - tx1) * TILE_YARDS
    return canvas, wx_max, wx_min, wy_max, wy_min


def main() -> None:
    try:
        os.nice(10)
    except OSError:
        pass

    parser = argparse.ArgumentParser(description="Generate SFUI overlay BLP2 DXT5 map tiles & LoD pack.")
    parser.add_argument(
        "--poc",
        action="store_true",
        help="Generate fast Tirisfal/Undercity PoC subset instead of the entire Forever world.",
    )
    parser.add_argument(
        "--caves-only",
        action="store_true",
        help="Rebuild only cave BLPs + manifest entries while preserving existing outdoor EK/Kalimdor and city BLPs.",
    )
    parser.add_argument(
        "--include-instances",
        action="store_true",
        help="Also generate Scarlet Monastery instance wing tiles (unreachable on Forever without UnitPosition).",
    )
    parser.add_argument(
        "--threads",
        type=int,
        default=24,
        help="Total CPU thread budget (clamped to 1..32; default 24).",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        help="Bounded chunk worker count (default min(threads, 12); clamped 1..24).",
    )
    parser.add_argument(
        "--max-rss-mb",
        type=int,
        default=28672,
        help="Hard RSS safety ceiling in MiB before aborting (default 28672).",
    )
    parser.add_argument(
        "--benchmark-chunk",
        action="store_true",
        help="Render only Stormwind 4x4 window without touching MEDIA_OUT, report peak RSS & elapsed time.",
    )
    args = parser.parse_args()
    threads = max(1, min(32, int(args.threads)))
    workers = min(threads, 12) if args.workers is None else max(1, min(24, int(args.workers)))
    cv2_threads = max(1, threads // workers)
    io_workers = min(threads, 24)
    cv2.setNumThreads(cv2_threads)

    t0 = time.perf_counter()
    casc = LocalCASC(WOW_ROOT, "wowf")
    wdt_bytes = casc.read_fid(AZEROTH_WDT_FID)
    maid_azeroth = wdt_bytes[wdt_bytes.index(b"DIAM") + 8 :]

    if args.benchmark_chunk:
        bt0 = time.perf_counter()
        _rgba, _has, _ocean = render_outdoor_window(
            casc, maid_azeroth, list(range(29, 33)), list(range(47, 51)), ROAD_TEX_FIDS, tile_px=TILE_PX
        )
        del _rgba, _has, _ocean
        gc.collect()
        rss_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0
        print(f"Benchmark 4x4 Stormwind chunk: rss={rss_mb:.1f} MB in {time.perf_counter() - bt0:.2f}s")
        return

    OVERLAY_UI_MEDIA.mkdir(parents=True, exist_ok=True)
    MEDIA_OUT.mkdir(parents=True, exist_ok=True)
    if args.caves_only:
        for pat in ("cave_*.tga", "cave_*.png", "cave_*.blp"):
            for old_f in MEDIA_OUT.glob(pat):
                old_f.unlink()
    else:
        for pat in (
            "ek_*.tga", "kal_*.tga", "city_*.tga", "uc_*.tga", "cave_*.tga", "sm_*.tga",
            "ek_*.png", "kal_*.png", "city_*.png", "uc_*.png", "cave_*.png", "sm_*.png",
            "ek_*.blp", "kal_*.blp", "city_*.blp", "uc_*.blp", "cave_*.blp", "sm_*.blp",
        ):
            for old_f in MEDIA_OUT.glob(pat):
                old_f.unlink()

    generate_radial_mask(OVERLAY_UI_MEDIA / "radial_mask.tga", size=256)
    generate_chevron_texture(OVERLAY_UI_MEDIA / "chevron_arrow.tga", size=64)

    cave_txt = (ADDONS_DIR / "OpenMap/Data/Forever/CaveMinimap.lua").read_text(encoding="utf-8")
    caves_lua_txt = (ADDONS_DIR / "OpenMap/Data/Forever/Caves.lua").read_text(encoding="utf-8")

    tile_jobs: list[tuple[Path, np.ndarray]] = []

    sm_meta = None
    sm_previews = None
    if args.include_instances:
        sm_meta, sm_previews = build_scarlet_monastery(casc, tile_px=TILE_PX, tile_jobs=tile_jobs)
        sm_cnt = sum(len(w["tiles"]) for w in sm_meta["wings"])  # type: ignore[union-attr]
        print(f"Prepared {sm_cnt} Scarlet Monastery BLP2 tiles across 4 wings ({TILE_PX}px)")

    vestibule_pins = [
        {"wx": 2926.0, "wy": -801.0, "kind": "portal", "title": "scarlet monastery: graveyard", "subtitle": "portal wing"},
        {"wx": 2925.0, "wy": -834.0, "kind": "portal", "title": "scarlet monastery: cathedral", "subtitle": "portal wing (key required)"},
        {"wx": 2884.0, "wy": -850.0, "kind": "portal", "title": "scarlet monastery: armory", "subtitle": "portal wing (key required)"},
        {"wx": 2862.0, "wy": -825.0, "kind": "portal", "title": "scarlet monastery: library", "subtitle": "portal wing"},
    ]

    if args.poc:
        outdoor_tiles, outdoor_rgba = build_outdoor(casc, wdt_bytes, tile_px=TILE_PX, tile_jobs=tile_jobs)
        print(f"Prepared {len(outdoor_tiles)} outdoor Tirisfal/Deathknell BLP2 tiles ({TILE_PX}px)")

        uc_meta, uc_rgba = build_undercity(casc, cave_txt, maid_azeroth, tile_px=TILE_PX, tile_jobs=tile_jobs)
        print(f"Prepared {len(uc_meta['tiles'])} Undercity BLP2 tiles ({TILE_PX}px)")

        caves, _ = build_caves(casc, maid_azeroth, caves_lua_txt, tile_px=TILE_PX, tile_jobs=tile_jobs, poc_only=True)
        print(f"Prepared {len(caves)} Tirisfal/Deathknell cave/crypt/vestibule BLP2 tiles ({TILE_PX}px)")

        with ThreadPoolExecutor(max_workers=io_workers) as pool:
            list(pool.map(lambda job: save_blp2_dxt5(job[0], job[1], magick_threads=1), tile_jobs))
        print(f"Encoded {len(tile_jobs)} BLP2 DXT5 (with mipmaps) tiles into {MEDIA_OUT}")

        qdb = index_questiedb_poc()
        write_lua_manifest(
            {0: outdoor_tiles},
            {1458: uc_meta},
            caves,
            sm_meta,
            vestibule_pins,
            qdb["subZoneToUiMapId"],  # type: ignore[arg-type]
        )
        print(f"Wrote {DATA_OUT}")

        uimap_bounds = {
            1420: (3033.3333, -1485.4167, 3837.5, 825.0),
            1458: (876.0417, -83.3333, 1879.1667, 1239.5833),
        }
        render_preview(
            ARTIFACT_DIR / "poc_undercity.png",
            uc_rgba,
            float(uc_meta["maxX"]),
            float(uc_meta["minX"]),
            float(uc_meta["maxY"]),
            float(uc_meta["minY"]),
            center_wx=1595.0,
            center_wy=240.0,
            view_radius=190.0,
            pins=qdb["previewPins"],  # type: ignore[arg-type]
            uimap_bounds=uimap_bounds,
            title="undercity :: cad contours/hatch + questiedb",
        )
        out_wx_max = (32 - min(OUTDOOR_TY_RANGE)) * TILE_YARDS
        out_wx_min = (31 - max(OUTDOOR_TY_RANGE)) * TILE_YARDS
        out_wy_max = (32 - min(OUTDOOR_TX_RANGE)) * TILE_YARDS
        out_wy_min = (31 - max(OUTDOOR_TX_RANGE)) * TILE_YARDS
        render_preview(
            ARTIFACT_DIR / "poc_deathknell.png",
            outdoor_rgba,
            out_wx_max,
            out_wx_min,
            out_wy_max,
            out_wy_min,
            center_wx=1860.0,
            center_wy=1605.0,
            view_radius=175.0,
            pins=qdb["previewPins"],  # type: ignore[arg-type]
            uimap_bounds=uimap_bounds,
            title="deathknell :: wmo walls + mcnr cliff hatch + questiedb",
        )
        render_preview(
            ARTIFACT_DIR / "poc_tirisfal_brill.png",
            outdoor_rgba,
            out_wx_max,
            out_wx_min,
            out_wy_max,
            out_wy_min,
            center_wx=2265.0,
            center_wy=385.0,
            view_radius=190.0,
            pins=qdb["previewPins"],  # type: ignore[arg-type]
            uimap_bounds=uimap_bounds,
            title="tirisfal glades (brill) :: wmo walls + contours + questiedb",
        )
    elif args.caves_only:
        preserved_continents, preserved_cities = _load_existing_continents_and_cities(DATA_OUT)
        print(
            f"Preserved {len(preserved_continents[0])} EK tiles, "
            f"{len(preserved_continents[1])} Kalimdor tiles, "
            f"and {len(preserved_cities)} cities from {DATA_OUT}"
        )
        caves, cave_previews = build_caves(
            casc,
            maid_azeroth,
            caves_lua_txt,
            tile_px=TILE_PX,
            tile_jobs=tile_jobs,
            poc_only=False,
            cave_minimap_txt=cave_txt,
        )
        with ThreadPoolExecutor(max_workers=io_workers) as pool:
            list(pool.map(lambda job: save_blp2_dxt5(job[0], job[1], magick_threads=1), tile_jobs))
        print(f"Encoded {len(tile_jobs)} cave BLP2 DXT5 tiles into {MEDIA_OUT}")

        subzone_map = load_forever_area_map()
        write_lua_manifest(
            preserved_continents,
            preserved_cities,
            caves,
            sm_meta,
            vestibule_pins,
            subzone_map,
        )
        print(f"Wrote {DATA_OUT}")

        preview_specs = [
            ("timbermaw", ARTIFACT_DIR / "cave_preview_timbermaw.png", "timbermaw hold :: caveminimap contours"),
            ("gnomeregan_ent", ARTIFACT_DIR / "cave_preview_gnomeregan.png", "gnomeregan entrance :: caveminimap contours"),
            ("forever_21067", ARTIFACT_DIR / "cave_preview_forever_21067.png", "forever cave 21067 :: caveminimap contours"),
        ]
        for pkey, out_png, ptitle in preview_specs:
            item = cave_previews.get(pkey)
            if not isinstance(item, tuple):
                continue
            ce, rgba, _cmt = item
            if "tiles" in ce:
                c_wx_max = float(ce["gridMaxX"])
                c_wy_max = float(ce["gridMaxY"])
                c_wx_min = c_wx_max - float(ce["rows"]) * float(ce["stepYards"])
                c_wy_min = c_wy_max - float(ce["cols"]) * float(ce["stepYards"])
            else:
                c_wx_max = float(ce["texMaxX"])
                c_wx_min = float(ce["texMinX"])
                c_wy_max = float(ce["texMaxY"])
                c_wy_min = float(ce["texMinY"])
            render_preview(
                out_png,
                rgba,
                c_wx_max,
                c_wx_min,
                c_wy_max,
                c_wy_min,
                center_wx=(float(ce["minX"]) + float(ce["maxX"])) * 0.5,
                center_wy=(float(ce["minY"]) + float(ce["maxY"])) * 0.5,
                view_radius=min(360.0, (c_wx_max - c_wx_min) * 0.48),
                pins=[],
                uimap_bounds={},
                title=ptitle,
            )
    else:
        wdt_kal = casc.read_fid(KALIMDOR_WDT_FID)
        maid_kal = wdt_kal[wdt_kal.index(b"DIAM") + 8 :]
        road_fids = discover_road_textures(casc, {0: maid_azeroth, 1: maid_kal}, max_workers=io_workers)
        print(f"Discovered {len(road_fids)} road overlay textures across EK & Kalimdor")

        sw_coords = [(tx, ty) for tx in range(29, 32) for ty in range(47, 50)]
        org_coords = [(tx, ty) for tx in range(39, 42) for ty in range(28, 31)]

        ek_tiles, ek_prev = build_continent_chunked(
            casc, 0, "ek", "eastern kingdoms", maid_azeroth, road_fids,
            tile_px=TILE_PX, max_workers=workers, max_rss_mb=args.max_rss_mb,
            magick_threads=cv2_threads, preview_coords=sw_coords,
        )
        kal_tiles, kal_prev = build_continent_chunked(
            casc, 1, "kal", "kalimdor", maid_kal, road_fids,
            tile_px=TILE_PX, max_workers=workers, max_rss_mb=args.max_rss_mb,
            magick_threads=cv2_threads, preview_coords=org_coords,
        )

        cities_meta, cities_rgba = build_cities(
            casc, cave_txt, maid_azeroth, city_ids=(1455, 1458), tile_px=TILE_PX, tile_jobs=tile_jobs
        )
        caves, cave_previews = build_caves(
            casc, maid_azeroth, caves_lua_txt, tile_px=TILE_PX, tile_jobs=tile_jobs, poc_only=False, cave_minimap_txt=cave_txt
        )

        with ThreadPoolExecutor(max_workers=io_workers) as pool:
            list(pool.map(lambda job: save_blp2_dxt5(job[0], job[1], magick_threads=1), tile_jobs))
        print(f"Encoded {len(tile_jobs)} city/cave/instance BLP2 DXT5 tiles into {MEDIA_OUT}")

        subzone_map = load_forever_area_map()
        write_lua_manifest(
            {0: ek_tiles, 1: kal_tiles},
            cities_meta,
            caves,
            sm_meta,
            vestibule_pins,
            subzone_map,
        )
        print(f"Wrote {DATA_OUT}")

        if 1455 in cities_meta and 1455 in cities_rgba:
            ifm = cities_meta[1455]
            render_preview(
                ARTIFACT_DIR / "world_preview_ironforge.png",
                cities_rgba[1455],
                float(ifm["maxX"]),
                float(ifm["minX"]),
                float(ifm["maxY"]),
                float(ifm["minY"]),
                center_wx=-4855.0,
                center_wy=-1080.0,
                view_radius=260.0,
                pins=[],
                uimap_bounds={},
                title="ironforge :: cad contours/hatch + wmo interior",
            )

        if sw_prev := _stitch_preview_tiles(ek_prev, 29, 31, 47, 49, tile_px=TILE_PX):
            render_preview(
                ARTIFACT_DIR / "world_preview_stormwind.png",
                sw_prev[0],
                sw_prev[1],
                sw_prev[2],
                sw_prev[3],
                sw_prev[4],
                center_wx=-8850.0,
                center_wy=620.0,
                view_radius=320.0,
                pins=[],
                uimap_bounds={},
                title="stormwind city :: wmo walls + canals + mcnr contours",
            )

        if org_prev := _stitch_preview_tiles(kal_prev, 39, 41, 28, 30, tile_px=TILE_PX):
            render_preview(
                ARTIFACT_DIR / "world_preview_orgrimmar_barrens.png",
                org_prev[0],
                org_prev[1],
                org_prev[2],
                org_prev[3],
                org_prev[4],
                center_wx=1580.0,
                center_wy=-4410.0,
                view_radius=320.0,
                pins=[],
                uimap_bounds={},
                title="orgrimmar & durotar :: wmo canyons + contours + roads",
            )

        brm = next((c for c in caves if c.get("uiMapID") == 33), None)
        if brm is not None and 33 in cave_previews:
            if "tiles" in brm:
                b_wx_max = float(brm["gridMaxX"])
                b_wy_max = float(brm["gridMaxY"])
                b_span_x = float(brm["rows"]) * float(brm["stepYards"])
                b_span_y = float(brm["cols"]) * float(brm["stepYards"])
                b_wx_min = b_wx_max - b_span_x
                b_wy_min = b_wy_max - b_span_y
            else:
                b_wx_max = float(brm["texMaxX"])
                b_wx_min = float(brm["texMinX"])
                b_wy_max = float(brm["texMaxY"])
                b_wy_min = float(brm["texMinY"])
            render_preview(
                ARTIFACT_DIR / "world_preview_blackrock_mtn.png",
                cave_previews[33],
                b_wx_max,
                b_wx_min,
                b_wy_max,
                b_wy_min,
                center_wx=(float(brm["minX"]) + float(brm["maxX"])) * 0.5,
                center_wy=(float(brm["minY"]) + float(brm["maxY"])) * 0.5,
                view_radius=min(280.0, (b_wx_max - b_wx_min) * 0.48),
                pins=[],
                uimap_bounds={},
                title="blackrock mountain :: 2x2 micro-map contours + rock relief",
            )

    if sm_meta is not None and sm_previews is not None:
        render_sm_showcase(ARTIFACT_DIR / "poc_scarlet_monastery.png", sm_meta, sm_previews)

    map_blps = list(MEDIA_OUT.glob("*.blp"))
    ui_tgas = list(OVERLAY_UI_MEDIA.glob("*.tga"))
    total_bytes = sum(p.stat().st_size for p in map_blps)
    ui_bytes = sum(p.stat().st_size for p in ui_tgas)
    print(
        f"Map pack size: {total_bytes / (1024 * 1024):.2f} MB across {len(map_blps)} BLP files "
        f"(UI media: {ui_bytes / 1024:.1f} KB across {len(ui_tgas)} TGA files) in {time.perf_counter() - t0:.1f}s"
    )


if __name__ == "__main__":
    main()
