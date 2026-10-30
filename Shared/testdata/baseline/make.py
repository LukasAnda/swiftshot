#!/usr/bin/env python3
"""Regenerates the baseline-comparison fixtures (inputs and expected JSON/JUnit).

Run with `python3 -I make.py` from anywhere. Stdlib only, deterministic. It rewrites each case's
`config.json`, `baseline/`, `output/` and `expected/{result.json,junit.xml,manifest.json}`.
`expected/images/` is left alone: the engine generates and commits those, and this script checks
them (baseline/new byte copies, diff images pixel- and byte-equal to `diff_image` below).

The expected values come from a reference implementation of docs/wiki/Baseline-format.md
below, checked against the numbers each synthetic edit is known to produce.
"""
import hashlib
import math
import os
import shutil
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.abspath(__file__))
COMMIT = "0123456789abcdef0123456789abcdef01234567"
BRANCH = "feature/x"
VERSION = "1.0.0-test"
CI = False
W, H = 40, 80


# ---------------------------------------------------------------- canonical JSON

def num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    assert abs(v) < 1e15, v
    if isinstance(v, int):
        return str(v)
    if v == math.floor(v):
        return str(int(v))
    r = repr(v)
    assert "e" not in r and "E" not in r, r
    return r


def quote(s):
    out = ['"']
    for c in s:
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif c == "\r":
            out.append("\\r")
        elif c == "\t":
            out.append("\\t")
        elif ord(c) < 0x20:
            out.append("\\u%04x" % ord(c))
        else:
            out.append(c)
    out.append('"')
    return "".join(out)


def key_order(k):
    return k.encode("utf-8")


def dump(v, indent="  ", pad=""):
    """Pretty form: 2 spaces, `"k": v`, sorted keys, `{}`/`[]` when empty."""
    if v is None:
        return "null"
    if isinstance(v, (bool, int, float)):
        return num(v)
    if isinstance(v, str):
        return quote(v)
    inner = pad + indent if indent is not None else ""
    nl = "\n" if indent is not None else ""
    if isinstance(v, dict):
        if not v:
            return "{}"
        sep = ": " if indent is not None else ":"
        items = [nl + inner + quote(k) + sep + dump(v[k], indent, inner) for k in sorted(v, key=key_order)]
        return "{" + ",".join(items) + nl + (pad if indent is not None else "") + "}"
    if isinstance(v, list):
        if not v:
            return "[]"
        items = [nl + inner + dump(x, indent, inner) for x in v]
        return "[" + ",".join(items) + nl + (pad if indent is not None else "") + "]"
    raise TypeError(type(v))


def pretty(v):
    return dump(v) + "\n"


def compact(v):
    return dump(v, indent=None)


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def fingerprint_id(fp):
    return sha(compact(fp))[:12]


# ---------------------------------------------------------------- PNG

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def encode(img, level=6, text=None):
    """The canonical encoding: RGBA 8-bit, filter 0, one IDAT; `text` adds a tEXt chunk."""
    w, h, px = img
    raw = b"".join(b"\x00" + bytes(px[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    if text:
        out += chunk(b"tEXt", text)
    return out + chunk(b"IDAT", zlib.compress(raw, level)) + chunk(b"IEND", b"")


def filtered(f, row, prev, bpp):
    out = bytearray(len(row))
    for i in range(len(row)):
        a = row[i - bpp] if i >= bpp else 0
        b = prev[i]
        c = prev[i - bpp] if i >= bpp else 0
        if f == 0:
            pred = 0
        elif f == 1:
            pred = a
        elif f == 2:
            pred = b
        elif f == 3:
            pred = (a + b) // 2
        else:
            pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
            pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
        out[i] = (row[i] - pred) & 255
    return bytes(out)


def encode_with(img, color_type=6, bit_depth=8, filters=(0,), idats=1):
    """Non-canonical encodings for decoder tests: RGB/RGBA, 8/16-bit, per-row filters, split IDAT."""
    w, h, px = img
    channels = 4 if color_type == 6 else 3
    bpp = channels * bit_depth // 8
    raw, prev = bytearray(), bytes(w * bpp)
    for y in range(h):
        row = bytearray()
        for x in range(w):
            for k in range(channels):
                v = px[(y * w + x) * 4 + k]
                row += bytes([v]) if bit_depth == 8 else struct.pack(">H", v * 257)
        f = filters[y % len(filters)]
        raw.append(f)
        raw += filtered(f, row, prev, bpp)
        prev = bytes(row)
    z = zlib.compress(bytes(raw), 6)
    cut = [len(z) * i // idats for i in range(idats + 1)]
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, bit_depth, color_type, 0, 0, 0))
    for i in range(idats):
        out += chunk(b"IDAT", z[cut[i]:cut[i + 1]])
    return out + chunk(b"IEND", b"")


def encode_palette(w, h, rgb):
    """A one-colour palette PNG (colour type 3): unsupported by the comparison."""
    raw = b"".join(b"\x00" + bytes(w) for _ in range(h))
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0))
    return out + chunk(b"PLTE", bytes(rgb)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


class Unsupported(Exception):
    pass


def png_size(data):
    return list(struct.unpack(">II", data[16:24]))


def decode(data):
    """The comparison's decoder: 8-bit RGB or RGBA, no interlace, any filter; samples as stored.
    Strict: anything malformed raises Unsupported."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise Unsupported()
    i, idat, ihdr = 8, b"", None
    while i < len(data):
        if i + 12 > len(data):
            raise Unsupported()
        n, = struct.unpack(">I", data[i:i + 4])
        kind, body = data[i + 4:i + 8], data[i + 8:i + 8 + n]
        if len(body) != n or i + 12 + n > len(data):
            raise Unsupported()
        crc, = struct.unpack(">I", data[i + 8 + n:i + 12 + n])
        if crc != zlib.crc32(kind + body) & 0xFFFFFFFF:
            raise Unsupported()
        i += 12 + n
        if (ihdr is None) != (kind == b"IHDR"):
            raise Unsupported()
        if kind == b"IHDR":
            if n != 13:
                raise Unsupported()
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if ihdr is None:
        raise Unsupported()
    w, h, depth, ctype, _, _, interlace = ihdr
    if depth != 8 or ctype not in (2, 6) or interlace != 0:
        raise Unsupported()
    bpp = 4 if ctype == 6 else 3
    try:
        raw = zlib.decompress(idat)
    except zlib.error:
        raise Unsupported()
    if len(raw) != h * (1 + w * bpp):
        raise Unsupported()
    prev, px, o = bytearray(w * bpp), bytearray(), 0
    for y in range(h):
        f, row = raw[o], bytearray(raw[o + 1:o + 1 + w * bpp])
        o += 1 + w * bpp
        if f > 4:
            raise Unsupported()
        for x in range(len(row)):
            a = row[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1:
                row[x] = (row[x] + a) & 255
            elif f == 2:
                row[x] = (row[x] + b) & 255
            elif f == 3:
                row[x] = (row[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                row[x] = (row[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        for x in range(w):
            px += row[x * bpp:x * bpp + 3] + (row[x * bpp + 3:x * bpp + 4] if bpp == 4 else b"\xff")
        prev = row
    return [w, h, px]


def base(seed, w=W, h=H):
    """Smooth pattern, every channel <= 200 so +delta edits never clamp."""
    px = bytearray(w * h * 4)
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 4
            px[i] = 40 + (x * 2 + seed * 13) % 100
            px[i + 1] = 60 + (y + seed * 29) % 100
            px[i + 2] = 120 + (seed * 7) % 60
            px[i + 3] = 255
    return [w, h, px]


def copy(img):
    return [img[0], img[1], bytearray(img[2])]


def fill(img, rect, rgba=(0, 0, 0, 255)):
    w = img[0]
    x0, y0, rw, rh = rect
    for y in range(y0, y0 + rh):
        for x in range(x0, x0 + rw):
            img[2][(y * w + x) * 4:(y * w + x) * 4 + 4] = bytes(rgba)
    return img


def shift(img, rect, delta):
    """Adds `delta` to the red channel."""
    w = img[0]
    x0, y0, rw, rh = rect
    for y in range(y0, y0 + rh):
        for x in range(x0, x0 + rw):
            img[2][(y * w + x) * 4] += delta
    return img


def grow(img, h):
    """Same content, taller: new rows continue the pattern of `base`."""
    w, oh, px = img
    out = base(0, w, h)
    out[2][:len(px)] = px
    return out


# ---------------------------------------------------------------- reference comparison

def scaled(rect, s, w, h):
    x, y, rw, rh = rect
    x0, y0 = max(0, math.floor(x * s)), max(0, math.floor(y * s))
    x1, y1 = min(w, math.ceil((x + rw) * s)), min(h, math.ceil((y + rh) * s))
    return x0, y0, x1, y1


def diff_mask(b, n, delta, regions, scale):
    bw, bh, bp = b
    nw, nh, np_ = n
    cw, ch = max(bw, nw), max(bh, nh)
    rects = [scaled(r, scale, cw, ch) for r in regions]
    mask = set()
    for y in range(ch):
        for x in range(cw):
            if any(x0 <= x < x1 and y0 <= y < y1 for x0, y0, x1, y1 in rects):
                continue
            if x >= bw or y >= bh or x >= nw or y >= nh:
                mask.add((x, y))
                continue
            i, j = (y * bw + x) * 4, (y * nw + x) * 4
            if any(abs(bp[i + k] - np_[j + k]) > delta for k in range(4)):
                mask.add((x, y))
    return mask


def boxes(mask):
    seen, comps = set(), []
    for p in sorted(mask, key=lambda q: (q[1], q[0])):
        if p in seen:
            continue
        stack, x0, y0, x1, y1 = [p], p[0], p[1], p[0] + 1, p[1] + 1
        seen.add(p)
        while stack:
            x, y = stack.pop()
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x + 1), max(y1, y + 1)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    q = (x + dx, y + dy)
                    if q in mask and q not in seen:
                        seen.add(q)
                        stack.append(q)
        comps.append([x0, y0, x1, y1])

    def gap(a, b):
        return max(0, b[0] - a[2], a[0] - b[2], b[1] - a[3], a[1] - b[3])

    merged = True
    while merged:
        merged = False
        for i in range(len(comps)):
            for j in range(i + 1, len(comps)):
                if gap(comps[i], comps[j]) < 16:
                    a, b = comps[i], comps[j]
                    comps[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                    del comps[j]
                    merged = True
                    break
            if merged:
                break
    out = [[x0, y0, x1 - x0, y1 - y0] for x0, y0, x1, y1 in comps]
    return sorted(out, key=lambda r: (r[1], r[0], r[2], r[3]))


DIFF_COLOR = (0xFF, 0x2D, 0x55, 255)


def diff_image(b, mask, cw, ch):
    """Canvas-sized, opaque: differing pixels #FF2D55, other baseline pixels at 30 % over white, the rest white."""
    bw, bh, bp = b
    px = bytearray(cw * ch * 4)
    for y in range(ch):
        for x in range(cw):
            o = (y * cw + x) * 4
            if (x, y) in mask:
                px[o:o + 4] = bytes(DIFF_COLOR)
            elif x < bw and y < bh:
                i = (y * bw + x) * 4
                a = bp[i + 3]
                for k in range(3):
                    c1 = (bp[i + k] * a + 255 * (255 - a) + 127) // 255
                    px[o + k] = (3 * c1 + 7 * 255 + 5) // 10
                px[o + 3] = 255
            else:
                px[o:o + 4] = b"\xff\xff\xff\xff"
    return [cw, ch, px]


def ascii_lower(s):
    return "".join(chr(ord(c) + 32) if "A" <= c <= "Z" else c for c in s)


def glob(pattern, name):
    parts = ascii_lower(pattern).split("*")
    s = ascii_lower(name)
    if len(parts) == 1:
        return s == parts[0]
    if not s.startswith(parts[0]) or not s.endswith(parts[-1]) or len(s) < len(parts[0]) + len(parts[-1]):
        return False
    i, end = len(parts[0]), len(s) - len(parts[-1])
    for p in parts[1:-1]:
        k = s.find(p, i, end)
        if k < 0:
            return False
        i = k + len(p)
    return True


def tolerance_for(config, preview, mode):
    rule = next((r for r in config.get("screens", []) if glob(r["preview"], preview)), None)
    if rule is not None and "tolerance" in rule:
        t = rule["tolerance"]
    elif "tolerance" in config:
        t = config["tolerance"]
    else:
        t = {"max_channel_delta": 1} if mode == "device" else {}
    regions = rule.get("ignore_regions", []) if rule else []
    return t.get("pixels", 0), t.get("max_channel_delta", 0), regions


def normalized(config):
    def tol(t):
        return {"max_channel_delta": t.get("max_channel_delta", 0), "pixels": t.get("pixels", 0)}
    screens = []
    for r in config.get("screens", []):
        s = {"preview": r["preview"]}
        if "tolerance" in r:
            s["tolerance"] = tol(r["tolerance"])
        if "ignore_regions" in r:
            s["ignore_regions"] = r["ignore_regions"]
        screens.append(s)
    return {"screens": screens, "tolerance": tol(config.get("tolerance", {}))}


def mismatches(base_fp, run_fp):
    out = []
    platform = run_fp["platform"]
    exact_ios = platform == "ios" or run_fp.get("renderer") == "exact-ios"
    for k in sorted(set(base_fp) | set(run_fp), key=key_order):
        a, b = base_fp.get(k), run_fp.get(k)
        if k == "host" and exact_ios:
            continue
        if k == "swiftshot" and a is not None and b is not None and a.split(".")[:2] == b.split(".")[:2]:
            continue
        if a != b:
            show = lambda v: "none" if v is None else ", ".join(v) if isinstance(v, list) else v
            out.append("%s %s: baseline %s, this run %s" % (platform, k, show(a), show(b)))
    return out


def image_fp(run_fp, img):
    """The fingerprint of one image of a run: an iOS run's `runtimes` (version -> build) become the
    image's own `runtime` build, looked up by the image's `runtime`; other fingerprints as they are."""
    fp = {k: v for k, v in run_fp.items() if k != "runtimes"}
    if "runtimes" in run_fp and img.get("runtime") in run_fp["runtimes"]:
        fp["runtime"] = run_fp["runtimes"][img["runtime"]]
    return fp


DESCRIPTIVE = ("platform", "module", "device", "language", "appearance", "preview", "fontScale", "textSize", "runtime")


def describe(meta):
    d = {k: meta[k] for k in DESCRIPTIVE if k in meta}
    if d["platform"] == "ios" and "textSize" not in d:
        d["textSize"] = "default"
    return d


def in_scope(img, scope):
    for field, key in (("platform", "platforms"), ("device", "devices"), ("language", "languages"),
                       ("appearance", "appearances"), ("fontScale", "fontScales"), ("textSize", "textSizes"),
                       ("module", "modules"), ("runtime", "runtimes")):
        if field in img and img[field] not in scope.get(key, []):
            return False
    globs = scope.get("previewFilter", [])
    return not globs or any(glob(g, img["preview"]) for g in globs)


def xml_attr(s):
    out = []
    for c in s:
        if c == "&":
            out.append("&amp;")
        elif c == "<":
            out.append("&lt;")
        elif c == ">":
            out.append("&gt;")
        elif c == '"':
            out.append("&quot;")
        elif c in "\t\n\r":
            out.append("&#%d;" % ord(c))
        elif ord(c) < 0x20:
            continue
        else:
            out.append(c)
    return "".join(out)


def run_host(run_fps):
    """One run, one host: every platform fingerprint carries it."""
    hosts = {fp["host"] for fp in run_fps.values()}
    assert len(hosts) <= 1, hosts
    return hosts.pop() if hosts else None


def verify(case):
    """The reference implementation of the format: returns (result, junit, manifest)."""
    report, baseline, config = case["report"], case["baseline_json"], case["config"]
    bfiles, ofiles = case["baseline_files"], case["output_files"]
    listed = baseline["images"]
    run_fps = report["fingerprint"]
    scope = report["scope"]
    out_imgs = {s["id"]: s for s in report["screenshots"]}
    failed = {}
    for err in report["errors"]:
        if "id" in err:
            failed.setdefault(err["id"], err["message"])  # first per id wins
    unattributed = [e for e in report["errors"] if "id" not in e]
    stray = {sid for sid in bfiles if sid not in listed}
    entries, compared, local = [], [], False
    for sid in sorted(set(out_imgs) | set(listed) | set(failed) | (stray & set(out_imgs)), key=key_order):
        b = listed.get(sid)
        o = out_imgs.get(sid)
        if o is None and sid not in failed and (not in_scope(b, scope) or unattributed):
            continue
        if b is not None:
            compared.append(b)
            local = local or b["local"]
        e = dict(describe(o) if o else describe(b) if b else {}, id=sid)
        err = (failed.get(sid)
               or (o is not None and sid not in ofiles and "output image missing")
               or (b is not None and sid not in bfiles and "baseline image missing")
               or (b is None and sid in bfiles and "baseline image not in baseline.json"))
        if not err and o is not None and b is not None and bfiles[sid] != ofiles[sid]:
            try:
                bi, ni = decode(bfiles[sid]), decode(ofiles[sid])
            except Unsupported:
                err = "unsupported PNG"
        if err:
            e.update(status="error", message=err)
            entries.append(e)
            continue
        if o is None:
            e.update(status="removed", baseline="images/baseline/%s.png" % sid)
            entries.append(e)
            continue
        if b is None:
            e.update(status="added", new="images/new/%s.png" % sid)
            entries.append(e)
            continue
        if bfiles[sid] == ofiles[sid]:
            e["status"] = "unchanged"
            entries.append(e)
            continue
        pixels_tol, delta, regions = tolerance_for(config, o["preview"], run_fps[o["platform"]]["mode"])
        mask = diff_mask(bi, ni, delta, regions, o["scale"])
        sized = bi[:2] != ni[:2]
        if not sized and len(mask) <= pixels_tol:
            e["status"] = "unchanged"
            if mask:
                e.update(reason="tolerance", pixels=len(mask))
            entries.append(e)
            continue
        e.update(status="changed", reason="size" if sized else "pixels", pixels=len(mask), boxes=boxes(mask),
                 baseline="images/baseline/%s.png" % sid, new="images/new/%s.png" % sid, diff="images/diff/%s.png" % sid)
        if sized:
            e.update(baselineSize=bi[:2], newSize=ni[:2])
        entries.append(e)

    mism = set()
    for b in compared:
        fp = baseline["fingerprints"][b["fingerprint"]]
        if fp["platform"] in run_fps:
            mism.update(mismatches(fp, image_fp(run_fps[fp["platform"]], b)))
    errors = [{"id": e["id"], "message": e["message"]} for e in entries if e["status"] == "error"] + unattributed
    counts = {k: sum(1 for e in entries if e["status"] == k) for k in ("unchanged", "changed", "added", "removed")}
    counts["errors"] = len(errors)
    status = "error" if errors else "failed" if counts["changed"] + counts["added"] + counts["removed"] else "passed"
    result = {
        "schema": 1, "status": status, "counts": counts, "commit": COMMIT, "branch": BRANCH, "version": VERSION,
        "ci": CI, "host": run_host(run_fps),
        "fingerprint": run_fps, "fingerprintMismatch": sorted(mism, key=key_order), "localBaseline": local,
        "screenshots": entries, "errors": errors, "strayBaselineFiles": len(stray - {e["id"] for e in entries}),
    }
    manifest = {
        "schema": 1, "commit": COMMIT, "branch": BRANCH, "ci": CI, "configHash": sha(compact(normalized(config))),
        "fingerprint": run_fps,
        "ids": {k: [e["id"] for e in entries if e["status"] == k] for k in ("changed", "added", "removed")},
    }
    failures = counts["changed"] + counts["added"] + counts["removed"]
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<testsuite name="swiftshot" tests="%d" failures="%d" errors="%d">' % (len(entries) + len(unattributed), failures, len(errors))]
    for e in entries:
        classname = "%s.%s.%s" % (e["platform"], e["device"], e["language"]) if "platform" in e else "swiftshot"
        attrs = 'classname="%s" name="%s"' % (xml_attr(classname), xml_attr(e["id"]))
        if e["status"] == "error":
            lines += ["  <testcase %s>" % attrs, '    <error message="%s"/>' % xml_attr(e["message"]), "  </testcase>"]
            continue
        if e["status"] == "changed":
            msg = ("changed: size %dx%d to %dx%d" % tuple(e["baselineSize"] + e["newSize"]) if e["reason"] == "size"
                   else "changed: %d pixels" % e["pixels"])
        elif e["status"] in ("added", "removed"):
            msg = e["status"]
        else:
            lines.append("  <testcase %s/>" % attrs)
            continue
        lines += ["  <testcase %s>" % attrs, '    <failure message="%s"/>' % xml_attr(msg), "  </testcase>"]
    for i, err in enumerate(unattributed, 1):
        lines += ['  <testcase classname="swiftshot" name="error %d">' % i,
                  '    <error message="%s"/>' % xml_attr(err["message"]), "  </testcase>"]
    lines.append("</testsuite>")
    return result, "\n".join(lines) + "\n", manifest


# ---------------------------------------------------------------- fixture building

FP = {
    "ios": {"host": "macos-arm64", "mode": "no-boot", "platform": "ios", "runtimes": {"26.0": "23A343"},
            "swiftshot": VERSION, "xcode": "17A400"},
    "android": {"compose": "1.9.0", "host": "linux-x64", "jdk": "21.0.8", "layoutlib": "16.0.1",
                "mode": "headless", "platform": "android", "swiftshot": VERSION},
    "flutter": {"flutter": "3.38.0", "fonts": ["MaterialIcons-Regular.otf", "Roboto-Regular.ttf"],
                "host": "linux-x64", "mode": "headless", "platform": "flutter", "renderer": "skia",
                "swiftshot": VERSION},
}


def ios(preview, appearance="light", device="iPhone 17 Pro", language="en-US", text_size=None, suffix=False, runtime="26.0", runtime_suffix=False):
    name = "%s-%s" % (device, preview) + ("-" + appearance if suffix else "") + ("-" + text_size if text_size else "")
    name += "-iOS" + runtime if runtime_suffix else ""
    m = {"platform": "ios", "device": device, "language": language, "appearance": appearance,
         "preview": preview, "runtime": runtime, "id": "%s/%s" % (language, name), "scale": 3}
    if text_size:
        m["textSize"] = text_size
    return m


def android(preview, appearance="light", device="Pixel 9", language="en-US", font_scale=1, platform="android", suffix=False, module=":app"):
    name = "%s-%s" % (device, preview) + ("-" + appearance if suffix else "") + ("-%sx" % num(font_scale) if font_scale != 1 else "")
    return {"platform": platform, "module": module, "device": device, "language": language, "appearance": appearance,
            "preview": preview, "fontScale": font_scale, "id": "%s/%s" % (language, name), "scale": 2.625}


def flutter(preview, **kw):
    m = android(preview, **kw)
    m["platform"] = "flutter"
    del m["module"]
    m["scale"] = 3
    return m


def report_entry(m, png):
    """A swiftshot-report.json screenshot, in the shape its platform's run writes."""
    w, h = png_size(png)
    e = {"file": m["id"] + ".png", "id": m["id"], "width": w, "height": h, "scale": m["scale"]}
    for k in DESCRIPTIVE:
        if k in m:
            e[k] = m[k]
    if m["platform"] == "ios":
        e["renderMs"] = 12.5
    else:
        e["millis"] = 120
    if m["platform"] == "android":
        e["composable"] = "com.example.ui.%sKt.%sPreview" % (m["preview"].replace(" ", ""), m["preview"].replace(" ", ""))
    if m["platform"] == "flutter":
        e["source"] = "lib/screens.dart:12"
    return e


def scope_of(metas, platforms=None, preview_filter=None, requested=None, **extra):
    """The rendered values, plus `requested` (the asked-for matrix, rendered or not)."""
    s = {
        "platforms": platforms or sorted({m["platform"] for m in metas}),
        "devices": sorted({m["device"] for m in metas}),
        "languages": sorted({m["language"] for m in metas}),
        "appearances": sorted({m["appearance"] for m in metas}),
        "previews": sorted({m["preview"] for m in metas}),
        "previewFilter": preview_filter or [],
        "modules": sorted({m["module"] for m in metas if "module" in m}),
        "runtimes": sorted({m["runtime"] for m in metas if "runtime" in m}),
    }
    if any(m["platform"] == "ios" for m in metas):
        s["textSizes"] = sorted({m.get("textSize", "default") for m in metas})
    if any("fontScale" in m for m in metas):
        s["fontScales"] = sorted({m["fontScale"] for m in metas if "fontScale" in m})
    for k, values in (requested or {}).items():
        s[k] = sorted(set(s.get(k, [])) | set(values))
    s.update(extra)
    return s


def baseline_entry(m, fp, is_local=False):
    e = {k: m[k] for k in DESCRIPTIVE if k in m}
    if m["platform"] == "ios" and "textSize" not in e:
        e["textSize"] = "default"
    e["fingerprint"] = fingerprint_id(fp)
    e["local"] = is_local
    return e


def png(item):
    return item if isinstance(item, bytes) else encode(item)


def case(name, baseline, output, config=None, scope=None, requested=None, errors=None, run_fp=None, base_fps=None,
         base_run_fp=None, local=(), missing_baseline=(), missing_output=(), stray=()):
    """baseline/output: lists of (meta, image or PNG bytes). run_fp: platform -> this run's fingerprint.
    The baseline images' fingerprints: base_fps (platform -> an image fingerprint), else those the run
    base_run_fp (default: this run) gave each image. missing_*: ids listed without a PNG on disk;
    stray: (id, image) PNGs not in baseline.json."""
    plats = sorted({m["platform"] for m, _ in output})
    host = "macos-arm64" if "ios" in plats else "linux-x64"
    run_fp = run_fp or {p: dict(FP[p], host=host) for p in plats}
    recorded = dict(FP, **(base_run_fp or run_fp))

    def base_fp(m):
        return base_fps[m["platform"]] if base_fps else image_fp(recorded[m["platform"]], m)
    metas = [m for m, _ in output]
    plats = sorted({m["platform"] for m, _ in output})
    report = {
        "errors": errors or [],
        "fingerprint": run_fp,
        "scope": scope or scope_of(metas, platforms=plats, requested=requested),
        "screenshots": sorted((report_entry(m, png(img)) for m, img in output), key=lambda e: key_order(e["id"])),
        "totalSeconds": 1.5,
    }
    if plats == ["ios"]:
        report["timings"] = {}
    else:
        report["platform"] = plats[0] if len(plats) == 1 else "android"
    fps = {fingerprint_id(base_fp(m)): base_fp(m) for m, _ in baseline}
    bjson = {"schema": 1, "fingerprints": fps,
             "images": {m["id"]: baseline_entry(m, base_fp(m), m["id"] in local) for m, _ in baseline}}
    bfiles = {m["id"]: png(img) for m, img in baseline if m["id"] not in missing_baseline}
    bfiles.update({sid: png(img) for sid, img in stray})
    ofiles = {m["id"]: png(img) for m, img in output if m["id"] not in missing_output}
    return {"name": name, "report": report, "baseline_json": bjson, "config": config or {},
            "baseline_files": bfiles, "output_files": ofiles}


def cases():
    out = []

    # Identical bytes everywhere; non-ASCII and XML-special names, a text size.
    imgs = [(ios("Home", suffix=True), base(1)), (ios("Home", "dark", suffix=True), base(2)), (ios("Terms & Privacy"), base(3)),
            (ios("Über"), base(4)), (ios("Home", text_size="AX2"), base(5))]
    out.append(case("unchanged", imgs, imgs))

    # Four edits: two 11 px apart merge into one box; one 37 px and one pixel 17 px away stay
    # separate; that pixel is off by a single red step and still counts (exact by default).
    b = base(7)
    n = fill(copy(b), [5, 5, 4, 4])
    fill(n, [5, 20, 3, 3])
    fill(n, [28, 60, 6, 6])
    shift(n, [20, 40, 1, 1], 1)
    out.append(case("changed-pixels", [(android("Home"), b), (android("Settings"), base(8))],
                    [(android("Home"), n), (android("Settings"), base(8))]))

    # 40x80 -> 40x96, top unchanged: 640 pixels, one box over the new rows.
    b = base(0)
    out.append(case("changed-size", [(flutter("Profile"), b)], [(flutter("Profile"), grow(b, 96))]))

    imgs = [(android("Home"), base(1))]
    out.append(case("added", imgs, imgs + [(android("Onboarding"), base(9))]))

    out.append(case("removed", imgs + [(android("Legacy"), base(9))], imgs))

    # Baseline images outside the run's scope, one dimension each, are not reported.
    imgs = [(ios("Home One"), base(1))]
    extra = [(ios("Home Two", language="de-DE"), base(2)), (ios("Home Two", device="iPad Air 11-inch (M3)"), base(3)),
             (ios("Home Two", "dark", suffix=True), base(4)), (ios("Home Two", text_size="XL"), base(5)),
             (ios("Settings"), base(6)), (android("Home One"), base(7))]
    out.append(case("out-of-scope", imgs + extra, imgs,
                    scope=dict(scope_of([m for m, _ in imgs], previewFilter=["home*"]), previews=["Home One"])))

    # Same pixels, PNG written with zlib level 1 and a tEXt chunk.
    b = base(3)
    m = ios("Home")
    out.append(case("same-pixels-different-bytes", [(m, b)], [(m, encode(b, level=1, text=b"Software\x00other encoder"))]))

    # The decoder: RGB (colour type 2) with filters 1-4 by row and two IDAT chunks, against the
    # canonical RGBA baseline. Same pixels -> unchanged; a 3x3 edit -> 9 pixels.
    mixed = dict(color_type=2, filters=(1, 2, 3, 4), idats=2)
    out.append(case("png-decoding", [(ios("Rgb Filters"), base(1)), (ios("Rgb Changed"), base(2))],
                    [(ios("Rgb Filters"), encode_with(base(1), **mixed)),
                     (ios("Rgb Changed"), encode_with(fill(copy(base(2)), [4, 4, 3, 3]), **mixed))]))

    # Global {pixels 5, max_channel_delta 1}; previews matching "clock*" replace it with
    # {max_channel_delta 2} (pixels 0). Glob is case-insensitive.
    home = shift(fill(copy(base(1)), [2, 2, 2, 2]), [10, 30, 5, 4], 1)    # 4 counted, 20 within delta
    settings = fill(copy(base(2)), [2, 2, 3, 2])                           # 6 counted
    clock = shift(copy(base(3)), [0, 0, 10, 3], 2)                         # 30 within delta 2
    clock_large = shift(shift(copy(base(4)), [0, 0, 10, 3], 2), [20, 70, 2, 1], 3)  # 2 counted
    out.append(case("tolerance",
                    [(android("Home"), base(1)), (android("Settings"), base(2)), (android("Clock"), base(3)), (android("Clock Large"), base(4))],
                    [(android("Home"), home), (android("Settings"), settings), (android("Clock"), clock), (android("Clock Large"), clock_large)],
                    config={"tolerance": {"pixels": 5, "max_channel_delta": 1}, "screens": [{"preview": "clock*", "tolerance": {"max_channel_delta": 2}}]}))

    # Regions in dp at scale 2.625: [0,0,16,4] -> px x 0..40 (clipped from 42), y 0..11;
    # [3.2,20,2,2] -> px x 8..14, y 52..58.
    feed = fill(copy(base(5)), [2, 2, 10, 5])      # entirely ignored
    fill(feed, [10, 50, 8, 6])                     # 48 changed, 16 of them ignored
    feed_dark = fill(copy(base(6)), [0, 0, 40, 11])
    out.append(case("ignore-region",
                    [(android("Feed", suffix=True), base(5)), (android("Feed", "dark", suffix=True), base(6))],
                    [(android("Feed", suffix=True), feed), (android("Feed", "dark", suffix=True), feed_dark)],
                    config={"screens": [{"preview": "Feed", "ignore_regions": [[0, 0, 16, 4], [3.2, 20, 2, 2]]}]}))

    # One baseline shared by an iOS job and an Android job (two fingerprints).
    shared = [(ios("Home"), base(1)), (ios("Settings"), base(2)), (android("Home"), base(3)), (android("Settings"), base(4))]
    out.append(case("split-run-ios", shared, [shared[0]]))
    out.append(case("split-run-android", shared, [shared[2], (android("Settings"), fill(copy(base(4)), [0, 0, 1, 1]))]))

    # Baseline recorded with other tools. Reported: iOS xcode and runtime, Android host and jdk.
    # Not reported: the swiftshot patch version, and the host for iOS.
    old_ios = image_fp(dict(FP["ios"], host="macos-x64", runtimes={"26.0": "23A300"}, swiftshot="1.0.3", xcode="17A324"), {"runtime": "26.0"})
    old_android = dict(FP["android"], host="linux-x64", jdk="21.0.5", swiftshot="1.0.3")
    imgs = [(ios("Home"), base(1)), (android("Home"), base(2))]
    out.append(case("fingerprint-mismatch", imgs, imgs, base_fps={"ios": old_ios, "android": old_android}))

    imgs = [(ios("Home"), base(1)), (ios("Settings"), base(2))]
    out.append(case("local-baseline", imgs, imgs, local={imgs[1][0]["id"]}))

    # Render errors with ids: status error (exit 2), never removed, also for a shot with no
    # baseline image (JUnit classname "swiftshot" then).
    imgs = [(android("Home"), base(1))]
    # Broken's baseline image is local: error entries count for localBaseline.
    out.append(case("render-error", imgs + [(android("Broken"), base(2))], imgs, local={"en-US/Pixel 9-Broken"},
                    errors=[{"id": "en-US/Pixel 9-Broken", "message": "IllegalStateException: boom"},
                            {"id": "en-US/Pixel 9-New", "message": "Timed out after 60 s"}]))

    # An error without an id (the run can't tell which shots it lost): no removals at all.
    out.append(case("build-error", imgs + [(android("Legacy"), base(2))], imgs,
                    errors=[{"message": ":feature: compilation failed"}]))

    # A --modules :app run: :feature's images are out of scope; :app's missing one is removed.
    out.append(case("module-filter", imgs + [(android("Legacy"), base(2)), (android("Detail", module=":feature"), base(3))], imgs))

    # One problem per id, plus precedence: render error > output image missing > baseline image
    # missing > not in baseline.json > unsupported PNG. A stray baseline PNG whose id the run
    # didn't produce is only counted (strayBaselineFiles); one with a render error is listed (the
    # render error) and not counted. Byte-equal files never get decoded; a bad CRC is unsupported.
    # The second error for one id is ignored.
    a = lambda p: android(p)
    sixteen = encode_with(base(6), bit_depth=16)
    palette = encode_palette(W, H, (10, 20, 30))
    corrupt = bytearray(encode(base(9)))
    corrupt[-20] ^= 0xFF  # a byte of the IDAT data: its CRC no longer matches
    corrupt = bytes(corrupt)
    out.append(case("comparison-errors",
                    [(a("Missing Baseline"), base(1)), (a("Missing Output"), base(2)), (a("Both Missing"), base(3)),
                     (a("Sixteen Bit"), base(6)), (a("Corrupt"), base(9)), (a("Palette Same"), palette), (a("Gone"), base(7)),
                     (a("Render And Missing"), base(8))],
                    [(a("Missing Baseline"), base(1)), (a("Missing Output"), base(2)), (a("Both Missing"), base(3)),
                     (a("Stray"), base(4)), (a("Sixteen Bit"), sixteen), (a("Corrupt"), corrupt), (a("Palette Same"), palette)],
                    missing_baseline={a("Missing Baseline")["id"], a("Both Missing")["id"], a("Gone")["id"], a("Render And Missing")["id"]},
                    missing_output={a("Missing Output")["id"], a("Both Missing")["id"]},
                    stray=[(a("Stray")["id"], base(4)), (a("Stray Old")["id"], base(5)), (a("Stray Broken")["id"], base(10))],
                    errors=[{"id": a("Render And Missing")["id"], "message": "IllegalStateException: boom"},
                            {"id": a("Render And Missing")["id"], "message": "second error for the same id: ignored"},
                            {"id": a("Stray Broken")["id"], "message": "Timed out after 60 s"}]))

    # Scope = requested matrix + rendered values: "Tablet Home" (the last preview on Pixel Tablet,
    # through a per-preview `devices` rule) was deleted; Pixel Tablet is still requested, so its
    # baseline image is removed.
    imgs = [(android("Home"), base(1))]
    out.append(case("deleted-preview", imgs + [(android("Tablet Home", device="Pixel Tablet"), base(2))], imgs,
                    requested={"devices": ["Pixel 9", "Pixel Tablet"]}))

    # Font scale alone and runtime alone exclude: an Android image at 1.3x (run: [1]) and an iOS
    # image on runtime 18.0 (run: ["26.0"]) are not reported.
    imgs = [(android("Home"), base(1)), (ios("Home"), base(2))]
    out.append(case("scope-scale-runtime",
                    imgs + [(android("Home", font_scale=1.3), base(3)), (ios("Home", runtime="18.0", runtime_suffix=True), base(4))],
                    imgs, base_run_fp={"ios": dict(FP["ios"], runtimes={"18.0": "22A3354", "26.0": "23A343"})}))

    # --mode device without a configured tolerance: max_channel_delta 1.
    dev = {"ios": dict(FP["ios"], mode="device")}
    out.append(case("device-mode",
                    [(ios("Glass"), base(1)), (ios("Blur"), base(2))],
                    [(ios("Glass"), shift(copy(base(1)), [0, 0, 40, 10], 1)), (ios("Blur"), shift(copy(base(2)), [0, 0, 3, 1], 2))],
                    run_fp=dev))

    # Images on two runtimes; this run has a newer build of 26.5 only. Each image's fingerprint
    # holds its own runtime's build, so only the 26.5 images differ.
    imgs = [(ios(p, runtime=r, runtime_suffix=True), base(i)) for i, (p, r) in enumerate(
        [("Home", "26.0"), ("Settings", "26.0"), ("Home", "26.5"), ("Settings", "26.5")])]
    two = dict(FP["ios"], runtimes={"26.0": "23A343", "26.5": "23F77"})
    out.append(case("multi-runtime", imgs, imgs, run_fp={"ios": dict(two, runtimes={"26.0": "23A343", "26.5": "23F80"})},
                    base_run_fp={"ios": two}))
    return out


# What each edit is known to produce; the reference comparison must agree.
KNOWN = {
    "changed-pixels": {"en-US/Pixel 9-Home": ("changed", 16 + 9 + 36 + 1, [[5, 5, 4, 18], [28, 60, 6, 6], [20, 40, 1, 1]])},
    "changed-size": {"en-US/Pixel 9-Profile": ("changed", 640, [[0, 80, 40, 16]])},
    "tolerance": {"en-US/Pixel 9-Home": ("unchanged", 4, None), "en-US/Pixel 9-Settings": ("changed", 6, [[2, 2, 3, 2]]),
                  "en-US/Pixel 9-Clock": ("unchanged", None, None), "en-US/Pixel 9-Clock Large": ("changed", 2, [[20, 70, 2, 1]])},
    "ignore-region": {"en-US/Pixel 9-Feed-light": ("changed", 32, [[10, 50, 8, 6]]), "en-US/Pixel 9-Feed-dark": ("unchanged", None, None)},
    "split-run-android": {"en-US/Pixel 9-Settings": ("changed", 1, [[0, 0, 1, 1]])},
    "png-decoding": {"en-US/iPhone 17 Pro-Rgb Filters": ("unchanged", None, None),
                     "en-US/iPhone 17 Pro-Rgb Changed": ("changed", 9, [[4, 4, 3, 3]])},
    "device-mode": {"en-US/iPhone 17 Pro-Glass": ("unchanged", None, None), "en-US/iPhone 17 Pro-Blur": ("changed", 3, [[0, 0, 3, 1]])},
}


def sort_boxes(bx):
    return sorted(bx, key=lambda r: (r[1], r[0], r[2], r[3]))


def check(c, result):
    for sid, (status, pixels, bx) in KNOWN.get(c["name"], {}).items():
        e = next(e for e in result["screenshots"] if e["id"] == sid)
        assert e["status"] == status, (c["name"], sid, e)
        assert e.get("pixels") == pixels, (c["name"], sid, e)
        assert e.get("boxes") == (sort_boxes(bx) if bx else None), (c["name"], sid, e)


def check_images(c, result, d):
    """expected/images (written by the engine) holds exactly the report's images: byte copies of the
    inputs, and diff images equal to diff_image() pixel for pixel and byte for byte (encode())."""
    want = {}
    for e in result["screenshots"]:
        sid = e["id"]
        if "baseline" in e:
            want[e["baseline"]] = c["baseline_files"][sid]
        if "new" in e:
            want[e["new"]] = c["output_files"][sid]
        if "diff" in e:
            bi, ni = decode(c["baseline_files"][sid]), decode(c["output_files"][sid])
            o = next(s for s in c["report"]["screenshots"] if s["id"] == sid)
            _, delta, regions = tolerance_for(c["config"], o["preview"], c["report"]["fingerprint"][o["platform"]]["mode"])
            mask = diff_mask(bi, ni, delta, regions, o["scale"])
            img = diff_image(bi, mask, max(bi[0], ni[0]), max(bi[1], ni[1]))
            path = os.path.join(d, "expected", e["diff"])
            if os.path.exists(path):
                with open(path, "rb") as f:
                    got = decode(f.read())
                assert got[:2] == img[:2] and bytes(got[2]) == bytes(img[2]), (c["name"], sid, "diff pixels")
            want[e["diff"]] = encode(img)
    images = os.path.join(d, "expected", "images")
    have = set()
    for dirpath, _, files in os.walk(images):
        have.update(os.path.relpath(os.path.join(dirpath, f), os.path.join(d, "expected")) for f in files)
    assert have == set(want), (c["name"], "expected/images", sorted(have ^ set(want)))
    for rel, data in want.items():
        with open(os.path.join(d, "expected", rel), "rb") as f:
            assert f.read() == data, (c["name"], rel, "bytes")


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))


def main():
    for c in cases():
        d = os.path.join(ROOT, c["name"])
        for sub in ("baseline", "output"):
            shutil.rmtree(os.path.join(d, sub), ignore_errors=True)
        for sid, data in c["baseline_files"].items():
            write(os.path.join(d, "baseline", sid + ".png"), data)
        for sid, data in c["output_files"].items():
            write(os.path.join(d, "output", sid + ".png"), data)
        write(os.path.join(d, "baseline", "baseline.json"), pretty(c["baseline_json"]))
        write(os.path.join(d, "output", "swiftshot-report.json"), pretty(c["report"]))
        write(os.path.join(d, "config.json"), pretty(c["config"]))
        result, junit, manifest = verify(c)
        check(c, result)
        write(os.path.join(d, "expected", "result.json"), pretty(result))
        write(os.path.join(d, "expected", "junit.xml"), junit)
        write(os.path.join(d, "expected", "manifest.json"), pretty(manifest))
        check_images(c, result, d)
        print("%-28s %s %s" % (c["name"], result["status"], dump(result["counts"], indent=None)))


if __name__ == "__main__":
    sys.exit(main())
