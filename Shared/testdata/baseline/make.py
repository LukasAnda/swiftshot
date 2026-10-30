#!/usr/bin/env python3
"""Regenerates the baseline-comparison fixtures (inputs and expected JSON/JUnit).

Run with `python3 -I make.py` from anywhere. Stdlib only, deterministic. It rewrites each case's
`config.json`, `baseline/`, `output/` and `expected/{result.json,junit.xml,manifest.json}`.
`expected/images/` is left alone: the engine generates and commits those.

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
W, H = 40, 80


# ---------------------------------------------------------------- canonical JSON

def num(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if v == math.floor(v) and abs(v) < 1e15:
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


def glob(pattern, name):
    parts = pattern.lower().split("*")
    s = name.lower()
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


DESCRIPTIVE = ("platform", "device", "language", "appearance", "preview", "fontScale", "textSize", "runtime")


def describe(meta):
    d = {k: meta[k] for k in DESCRIPTIVE if k in meta}
    if d["platform"] == "ios" and "textSize" not in d:
        d["textSize"] = "default"
    return d


def in_scope(img, scope):
    for field, key in (("platform", "platforms"), ("device", "devices"), ("language", "languages"),
                       ("appearance", "appearances"), ("fontScale", "fontScales"), ("textSize", "textSizes")):
        if field in img and img[field] not in scope.get(key, []):
            return False
    globs = scope.get("previewFilter", [])
    return not globs or any(glob(g, img["preview"]) for g in globs)


def scale_label(d):
    if "fontScale" in d and d["fontScale"] != 1:
        return " " + num(d["fontScale"]) + "x"
    if "textSize" in d and d["textSize"] != "default":
        return " " + d["textSize"]
    return ""


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


def verify(case):
    """The reference implementation of the format: returns (result, junit, manifest)."""
    report, baseline, config = case["report"], case["baseline_json"], case["config"]
    run_fps = report["fingerprint"]
    scope = report["scope"]
    out_imgs = {s["id"]: s for s in report["screenshots"]}
    entries, compared_fps, local = [], set(), False
    for sid in sorted(set(out_imgs) | set(baseline["images"]), key=key_order):
        b = baseline["images"].get(sid)
        o = out_imgs.get(sid)
        if b is not None:
            if not in_scope(b, scope) and o is None:
                continue
            compared_fps.add(b["fingerprint"])
            local = local or b["local"]
        if o is None:
            e = dict(describe(b), id=sid, status="removed", baseline="images/baseline/%s.png" % sid)
            entries.append(e)
            continue
        e = dict(describe(o), id=sid)
        if b is None:
            e.update(status="added", new="images/new/%s.png" % sid)
            entries.append(e)
            continue
        bb, nb = case["baseline_png"][sid], case["output_png"][sid]
        if bb == nb:
            e["status"] = "unchanged"
            entries.append(e)
            continue
        bi, ni = case["baseline_img"][sid], case["output_img"][sid]
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
    for f in compared_fps:
        fp = baseline["fingerprints"][f]
        if fp["platform"] in run_fps:
            mism.update(mismatches(fp, run_fps[fp["platform"]]))
    errors = list(report["errors"])
    counts = {k: sum(1 for e in entries if e["status"] == k) for k in ("unchanged", "changed", "added", "removed")}
    counts["errors"] = len(errors)
    status = "error" if errors else "failed" if counts["changed"] + counts["added"] + counts["removed"] else "passed"
    result = {
        "schema": 1, "status": status, "counts": counts, "commit": COMMIT, "branch": BRANCH, "version": VERSION,
        "fingerprint": run_fps, "fingerprintMismatch": sorted(mism, key=key_order), "localBaseline": local,
        "screenshots": entries, "errors": errors,
    }
    manifest = {
        "schema": 1, "commit": COMMIT, "branch": BRANCH, "configHash": sha(compact(normalized(config))),
        "fingerprint": run_fps,
        "ids": {k: [e["id"] for e in entries if e["status"] == k] for k in ("changed", "added", "removed")},
    }
    failures = counts["changed"] + counts["added"] + counts["removed"]
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             '<testsuite name="swiftshot" tests="%d" failures="%d" errors="%d">' % (len(entries) + len(errors), failures, len(errors))]
    for e in entries:
        attrs = 'classname="%s" name="%s"' % (xml_attr("%s.%s.%s" % (e["platform"], e["device"], e["language"])),
                                              xml_attr("%s %s%s" % (e["preview"], e["appearance"], scale_label(e))))
        if e["status"] == "changed":
            msg = ("changed: size %dx%d to %dx%d" % tuple(e["baselineSize"] + e["newSize"]) if e["reason"] == "size"
                   else "changed: %d pixels" % e["pixels"])
        elif e["status"] in ("added", "removed"):
            msg = e["status"]
        else:
            lines.append("  <testcase %s/>" % attrs)
            continue
        lines += ["  <testcase %s>" % attrs, '    <failure message="%s"/>' % xml_attr(msg), "  </testcase>"]
    for i, err in enumerate(errors, 1):
        lines += ['  <testcase classname="swiftshot" name="error %d">' % i,
                  '    <error message="%s"/>' % xml_attr(err), "  </testcase>"]
    lines.append("</testsuite>")
    return result, "\n".join(lines) + "\n", manifest


# ---------------------------------------------------------------- fixture building

FP = {
    "ios": {"host": "macos-arm64", "mode": "no-boot", "platform": "ios", "runtime": "23A343",
            "swiftshot": VERSION, "xcode": "17A400"},
    "android": {"compose": "1.9.0", "host": "linux-x64", "jdk": "21.0.8", "layoutlib": "16.0.1",
                "mode": "headless", "platform": "android", "swiftshot": VERSION},
    "flutter": {"flutter": "3.38.0", "fonts": ["MaterialIcons-Regular.otf", "Roboto-Regular.ttf"],
                "host": "linux-x64", "mode": "headless", "platform": "flutter", "renderer": "skia",
                "swiftshot": VERSION},
}


def ios(preview, appearance="light", device="iPhone 17 Pro", language="en-US", text_size=None, suffix=False):
    name = "%s-%s" % (device, preview) + ("-" + appearance if suffix else "") + ("-" + text_size if text_size else "")
    m = {"platform": "ios", "device": device, "language": language, "appearance": appearance,
         "preview": preview, "runtime": "26.0", "id": "%s/%s" % (language, name), "scale": 3}
    if text_size:
        m["textSize"] = text_size
    return m


def android(preview, appearance="light", device="Pixel 9", language="en-US", font_scale=1, platform="android", suffix=False):
    name = "%s-%s" % (device, preview) + ("-" + appearance if suffix else "") + ("-%sx" % num(font_scale) if font_scale != 1 else "")
    return {"platform": platform, "device": device, "language": language, "appearance": appearance,
            "preview": preview, "fontScale": font_scale, "id": "%s/%s" % (language, name), "scale": 2.625}


def flutter(preview, **kw):
    m = android(preview, **kw)
    m["platform"] = "flutter"
    m["scale"] = 3
    return m


def report_entry(m, img):
    """A swiftshot-report.json screenshot, in the shape its platform's run writes."""
    e = {"file": m["id"] + ".png", "id": m["id"], "width": img[0], "height": img[1], "scale": m["scale"]}
    for k in DESCRIPTIVE:
        if k in m:
            e[k] = m[k]
    if m["platform"] == "ios":
        e["renderMs"] = 12.5
    else:
        e["millis"] = 120
    if m["platform"] == "android":
        e["module"] = ":app"
        e["composable"] = "com.example.ui.%sKt.%sPreview" % (m["preview"].replace(" ", ""), m["preview"].replace(" ", ""))
    if m["platform"] == "flutter":
        e["source"] = "lib/screens.dart:12"
    return e


def scope_of(metas, platforms=None, preview_filter=None, **extra):
    s = {
        "platforms": platforms or sorted({m["platform"] for m in metas}),
        "devices": sorted({m["device"] for m in metas}),
        "languages": sorted({m["language"] for m in metas}),
        "appearances": sorted({m["appearance"] for m in metas}),
        "previews": sorted({m["preview"] for m in metas}),
        "previewFilter": preview_filter or [],
    }
    if any(m["platform"] == "ios" for m in metas):
        s["textSizes"] = sorted({m.get("textSize", "default") for m in metas})
    if any("fontScale" in m for m in metas):
        s["fontScales"] = sorted({m["fontScale"] for m in metas if "fontScale" in m})
    s.update(extra)
    return s


def baseline_entry(m, fp, is_local=False):
    e = {k: m[k] for k in DESCRIPTIVE if k in m}
    if m["platform"] == "ios" and "textSize" not in e:
        e["textSize"] = "default"
    e["fingerprint"] = fingerprint_id(fp)
    e["local"] = is_local
    return e


def case(name, baseline, output, config=None, scope=None, errors=None, run_fp=None, base_fps=None, local=(), raw_output=None):
    """baseline/output: lists of (meta, image). run_fp/base_fps: platform -> fingerprint."""
    run_fp = run_fp or {p: FP[p] for p in sorted({m["platform"] for m, _ in output})}
    base_fps = base_fps or FP
    metas = [m for m, _ in output]
    plats = sorted({m["platform"] for m, _ in output})
    report = {
        "errors": errors or [],
        "fingerprint": run_fp,
        "scope": scope or scope_of(metas, platforms=plats),
        "screenshots": sorted((report_entry(m, img) for m, img in output), key=lambda e: key_order(e["id"])),
        "totalSeconds": 1.5,
    }
    if plats == ["ios"]:
        report["timings"] = {}
    else:
        report["platform"] = plats[0] if len(plats) == 1 else "android"
    fps = {fingerprint_id(base_fps[m["platform"]]): base_fps[m["platform"]] for m, _ in baseline}
    bjson = {"schema": 1, "fingerprints": fps,
             "images": {m["id"]: baseline_entry(m, base_fps[m["platform"]], m["id"] in local) for m, _ in baseline}}
    c = {
        "name": name, "report": report, "baseline_json": bjson, "config": config or {},
        "baseline_img": {m["id"]: img for m, img in baseline}, "output_img": {m["id"]: img for m, img in output},
    }
    c["baseline_png"] = {k: encode(v) for k, v in c["baseline_img"].items()}
    c["output_png"] = {k: encode(v) for k, v in c["output_img"].items()}
    c["output_png"].update(raw_output or {})
    return c


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
    out.append(case("same-pixels-different-bytes", [(m, b)], [(m, b)],
                    raw_output={m["id"]: encode(b, level=1, text=b"Software\x00other encoder")}))

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
    old_ios = dict(FP["ios"], host="macos-x64", runtime="23A300", swiftshot="1.0.3", xcode="17A324")
    old_android = dict(FP["android"], host="macos-arm64", jdk="21.0.5", swiftshot="1.0.3")
    imgs = [(ios("Home"), base(1)), (android("Home"), base(2))]
    out.append(case("fingerprint-mismatch", imgs, imgs, base_fps={"ios": old_ios, "android": old_android}))

    imgs = [(ios("Home"), base(1)), (ios("Settings"), base(2))]
    out.append(case("local-baseline", imgs, imgs, local={imgs[1][0]["id"]}))

    # A render error: status error (exit 2), a JUnit <error>, counts.errors.
    imgs = [(android("Home"), base(1))]
    out.append(case("render-error", imgs, imgs, errors=["Broken · Pixel 9 · en-US: IllegalStateException: boom"]))

    # --mode device without a configured tolerance: max_channel_delta 1.
    dev = {"ios": dict(FP["ios"], mode="device")}
    out.append(case("device-mode",
                    [(ios("Glass"), base(1)), (ios("Blur"), base(2))],
                    [(ios("Glass"), shift(copy(base(1)), [0, 0, 40, 10], 1)), (ios("Blur"), shift(copy(base(2)), [0, 0, 3, 1], 2))],
                    run_fp=dev, base_fps=dev))
    return out


# What each edit is known to produce; the reference comparison must agree.
KNOWN = {
    "changed-pixels": {"en-US/Pixel 9-Home": ("changed", 16 + 9 + 36 + 1, [[5, 5, 4, 18], [28, 60, 6, 6], [20, 40, 1, 1]])},
    "changed-size": {"en-US/Pixel 9-Profile": ("changed", 640, [[0, 80, 40, 16]])},
    "tolerance": {"en-US/Pixel 9-Home": ("unchanged", 4, None), "en-US/Pixel 9-Settings": ("changed", 6, [[2, 2, 3, 2]]),
                  "en-US/Pixel 9-Clock": ("unchanged", None, None), "en-US/Pixel 9-Clock Large": ("changed", 2, [[20, 70, 2, 1]])},
    "ignore-region": {"en-US/Pixel 9-Feed-light": ("changed", 32, [[10, 50, 8, 6]]), "en-US/Pixel 9-Feed-dark": ("unchanged", None, None)},
    "split-run-android": {"en-US/Pixel 9-Settings": ("changed", 1, [[0, 0, 1, 1]])},
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


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))


def main():
    for c in cases():
        d = os.path.join(ROOT, c["name"])
        for sub in ("baseline", "output"):
            shutil.rmtree(os.path.join(d, sub), ignore_errors=True)
        for sid, png in c["baseline_png"].items():
            write(os.path.join(d, "baseline", sid + ".png"), png)
        for sid, png in c["output_png"].items():
            write(os.path.join(d, "output", sid + ".png"), png)
        write(os.path.join(d, "baseline", "baseline.json"), pretty(c["baseline_json"]))
        write(os.path.join(d, "output", "swiftshot-report.json"), pretty(c["report"]))
        write(os.path.join(d, "config.json"), pretty(c["config"]))
        result, junit, manifest = verify(c)
        check(c, result)
        write(os.path.join(d, "expected", "result.json"), pretty(result))
        write(os.path.join(d, "expected", "junit.xml"), junit)
        write(os.path.join(d, "expected", "manifest.json"), pretty(manifest))
        print("%-28s %s %s" % (c["name"], result["status"], dump(result["counts"], indent=None)))


if __name__ == "__main__":
    sys.exit(main())
