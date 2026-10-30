The files `verify`, `record` and `accept` read and write. Both implementations (the Swift binary
and the JVM CLI) follow this page exactly and are tested against the fixtures in
`Shared/testdata/baseline` (regenerate inputs with `python3 -I Shared/testdata/baseline/make.py`).

## Layout

```
<baseline_directory>/                 default screenshots-baseline
  <id>.png
  baseline.json
<output_directory>/                   what the run wrote
  <id>.png
  swiftshot-report.json
<report_directory>/                   default <output_directory>-report
  result.json
  junit.xml
  index.html
  manifest.json
  images/baseline/<id>.png            changed and removed
  images/new/<id>.png                 changed and added
  images/diff/<id>.png                changed
```

**Screenshot id**: the PNG's path relative to the output directory, `/`-separated, without `.png`,
e.g. `de-DE/iPhone 17 Pro-Welcome-dark`. File names are the ones `run` writes today (appearance,
text size, font scale, iOS runtime parts included).

Examples below are abbreviated and not in the sorted key order the files use.

## Exit codes

| code | |
|---|---|
| 0 | no differences |
| 1 | differences (changed, added or removed) |
| 2 | errors, with or without differences |
| 64 | usage error |

## Serialization

**JSON** (every file on this page):

- Keys sorted by their UTF-8 bytes.
- Pretty: 2-space indent, `"key": value`, one element per line, every non-empty array and
  object expanded (also `[x, y, w, h]` boxes), empty ones as `[]` and `{}`, a final `\n`.
  Compact (used for hashes only): the same with no whitespace at all.
- Strings: escape `"` `\` as `\"` `\\`, LF CR TAB as `\n` `\r` `\t`, other characters below
  U+0020 as `\u00xx` (lowercase hex). Nothing else is escaped (not `/`, not non-ASCII).
- Numbers: an integral value is written as an integer (`1.0` → `1`); others in the shortest
  decimal form that round-trips, never with an exponent (`2.625`, `1.3`).
- Arrays of ids or messages are sorted by UTF-8 bytes unless stated otherwise.

**Hash**: lowercase hex SHA-256 of the compact JSON's UTF-8 bytes.

**PNG** (diff images; baseline and new images are byte copies): 8-bit RGBA (colour type 6),
interlace 0, filter type 0 on every row, chunks `IHDR`, one `IDAT`, `IEND` and nothing else. The
`IDAT` is one zlib stream: deflate level 6, window 15, memory level 8, default strategy, as zlib's
`compress2(…, 6)` and Java's `new Deflater(6)` + `finish()` write it (verified identical with zlib
1.2.12).

**Decoding** (for comparison): bit depth 8, colour type 6 (RGBA) or 2 (RGB, alpha 255), any filter,
interlace 0; all other chunks ignored. Samples are used as stored: no colour management, no
premultiplication. Any other PNG is an error `<id>: unsupported PNG`.

**Determinism**: `commit`, `branch`, `version` come from `SWIFTSHOT_COMMIT`, `SWIFTSHOT_BRANCH`
and `SWIFTSHOT_VERSION_OVERRIDE` when set (tests set them: `0123456789abcdef0123456789abcdef01234567`,
`feature/x`, `1.0.0-test`). Otherwise from git/CI and the binary; unknown is `null`.

## swiftshot-report.json additions

The run report keeps its current keys and gains:

- `fingerprint`: platform → fingerprint (below), one per platform the run rendered.
- `scope`: what the run covered.
  ```json
  {"platforms": ["ios"], "devices": ["iPhone 17 Pro"], "languages": ["en-US"],
   "appearances": ["light", "dark"], "textSizes": ["default"], "fontScales": [1, 1.3],
   "previews": ["Home", "Settings"], "previewFilter": ["Home*"]}
  ```
  `textSizes` when iOS was rendered (`"default"` = the device's own), `fontScales` when Android,
  desktop or Flutter was. `previews`: the preview names the run found after filters (informational).
  `previewFilter`: the `--previews` globs, `[]` when none. All lists sorted (`fontScales` by value).
- Per screenshot: `id`, `platform` (`ios`, `android`, `desktop`, `flutter`) and `scale` (pixels per
  point/dp, e.g. `3`, `2.625`). Existing per-screenshot keys used here: `preview`, `device`,
  `language`, `appearance`, `fontScale` (Android, desktop, Flutter), `textSize` (iOS, absent =
  `"default"`), `runtime` (iOS).

The verify inputs are the report's `screenshots`, `errors`, `scope` and `fingerprint`; the output
directory is not listed.

## Fingerprint

| field | platforms | |
|---|---|---|
| `platform` | all | `ios`, `android`, `desktop`, `flutter` |
| `host` | all | `macos-arm64`, `macos-x64`, `linux-x64`, `linux-arm64` |
| `swiftshot` | all | version |
| `mode` | all | `no-boot`, `device` (iOS); `headless` (Android, desktop, Flutter); `exact-ios` (Flutter) |
| `xcode`, `runtime` | ios | build numbers (`17A400`, `23A343`) |
| `layoutlib`, `compose`, `jdk` | android, desktop | versions from the resolved classpath |
| `flutter`, `renderer`, `fonts` | flutter | version; `impeller`, `skia` or `exact-ios`; sorted font file names |

Values are strings, `fonts` an array of strings. **Fingerprint id**: the first 12 hex digits of the
fingerprint's hash.

**Pixel-relevant**: every field, except `swiftshot` compares only its first two `.`-separated parts
(`1.0.3` = `1.0.0-test`), and `host` is ignored when `platform` is `ios` or `renderer` is
`exact-ios`. A field present on one side only is a difference (the other shown as `none`).

## baseline.json

```json
{
  "schema": 1,
  "fingerprints": {"d2d5c0db8687": {"host": "macos-arm64", "mode": "no-boot", "platform": "ios", …}},
  "images": {
    "en-US/iPhone 17 Pro-Home": {"fingerprint": "d2d5c0db8687", "platform": "ios", "device": "iPhone 17 Pro",
      "language": "en-US", "appearance": "light", "preview": "Home", "textSize": "default", "runtime": "26.0", "local": false},
    "en-US/Pixel 9-Home": {"fingerprint": "7d572793275d", "platform": "android", "device": "Pixel 9",
      "language": "en-US", "appearance": "light", "preview": "Home", "fontScale": 1, "local": false}
  }
}
```

- Every image references one entry of `fingerprints`; unreferenced fingerprints are dropped on write.
- iOS images have `textSize` (`"default"` when none) and `runtime`; the others `fontScale`.
- `local`: `true` when the image was rendered outside CI (`record` on a developer machine).

The baseline set is `images`. An image that is compared or removed but has no PNG is an error
`<id>: baseline image missing`; a PNG under the baseline directory that is not in `images` is an
error `<id>: baseline image not in baseline.json`. A report screenshot without its PNG is an error
`<id>: output image missing`.

## Comparison config

`swiftshot.json` keys (the fixtures' `config.json` holds exactly these):

```json
{"tolerance": {"pixels": 5, "max_channel_delta": 1},
 "screens": [{"preview": "Clock*", "tolerance": {"max_channel_delta": 2}},
             {"preview": "Feed", "ignore_regions": [[0, 0, 16, 4]]}]}
```

- `tolerance.max_channel_delta` d (default 0): a pixel differs when any of R, G, B, A differs by
  more than d. `tolerance.pixels` n (default 0): up to n differing pixels still count as unchanged.
  Both may be set.
- `screens`: the first rule whose `preview` glob matches the preview name applies (as for all
  `screens` keys; glob: `*` = any run of characters, whole name, ASCII case-insensitive). Its
  `tolerance` replaces the global one; its `ignore_regions` apply.
- Without any tolerance for a screenshot (neither the rule nor the global one), a screenshot whose
  platform fingerprint has `mode` `device` uses `{"max_channel_delta": 1}`; all others exact.
- `ignore_regions`: `[x, y, w, h]` in points (iOS) or dp, times the screenshot's `scale`:
  `x0 = floor(x·s)`, `y0 = floor(y·s)`, `x1 = ceil((x+w)·s)`, `y1 = ceil((y+h)·s)` (double
  precision, in that order), clipped to the canvas; pixels with `x0 ≤ x < x1`, `y0 ≤ y < y1` never
  differ.

**configHash**: the hash of the normalized config:
`{"screens": [<every rule in order: "preview", plus "tolerance" and "ignore_regions" when set>], "tolerance": T}`,
every tolerance written with both keys (`{"max_channel_delta": d, "pixels": n}`, absent = 0). Rules
with other keys only appear as `{"preview": …}`. The `mode` default above is not part of it.

## Status

For every id in the output (report `screenshots`) or the baseline (`images`):

| | condition |
|---|---|
| `added` | in the output, not in the baseline |
| `removed` | in the baseline and in scope, not in the output |
| `unchanged` | both, and the PNG bytes are equal, or the comparison passes |
| `changed` | both, and the comparison fails |

Baseline images that are not in scope and not in the output are left out entirely (not listed,
not counted, no fingerprint check).

**In scope**: `platform` ∈ `platforms`, `device` ∈ `devices`, `language` ∈ `languages`,
`appearance` ∈ `appearances`, `textSize` ∈ `textSizes` (if the image has one), `fontScale` ∈
`fontScales` (if the image has one, compared as numbers), and `previewFilter` is empty or one of
its globs matches `preview`. A list missing from the scope matches nothing.

**Comparison** (bytes differ): decode both. Canvas = max width × max height. A canvas pixel
differs when it lies outside either image, or the channel rule says so; then ignore regions are
removed. `pixels` = number of differing pixels.

- Sizes differ → `changed`, reason `size` (always, whatever the tolerance), with `baselineSize`
  and `newSize` `[w, h]`.
- Else `pixels` ≤ n → `unchanged`; reason `tolerance` and `pixels` when `pixels` > 0.
- Else `changed`, reason `pixels`.

**Boxes** (changed only), on the canvas's differing pixels: 8-connected components, each as its
bounding box, half-open `[x0, x1) × [y0, y1)`. Two boxes are close when
`max(0, b.x0−a.x1, a.x0−b.x1, b.y0−a.y1, a.y0−b.y1) < 16`; replace any close pair by its union
until no pair is close (the result does not depend on the order). Written as `[x, y, w, h]`,
sorted by y, x, w, h.

**Diff image** (changed only), canvas-sized, opaque: a differing pixel is `#FF2D55`; any other
pixel inside the baseline is the baseline at 30 % over white; the rest is white. With baseline
sample c and alpha a (0–255), in integers:
`c1 = (c·a + 255·(255−a) + 127) / 255`, `out = (3·c1 + 7·255 + 5) / 10` (`/` truncates), alpha 255.

**Errors** (`errors`, in this order): the report's `errors` as given, then comparison errors
sorted. An id with an error (missing or undecodable image) is left out of `screenshots`.

**Fingerprint mismatch**: for every distinct baseline fingerprint referenced by a listed baseline
image (unchanged, changed or removed), compare it with the run's fingerprint for its platform (none: skipped).
Each pixel-relevant difference is a message `<platform> <field>: baseline <value>, this run <value>`
(arrays joined with `, `, absent = `none`); duplicates dropped, sorted. `verify` prints these
first; they never change the status.

**localBaseline**: `true` when a listed baseline image has `local: true`. A warning, never a failure.

## result.json

```json
{
  "schema": 1,
  "status": "failed",
  "counts": {"added": 0, "changed": 1, "errors": 0, "removed": 0, "unchanged": 1},
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "branch": "feature/x",
  "version": "1.0.0-test",
  "fingerprint": {"android": {…}},
  "fingerprintMismatch": [],
  "localBaseline": false,
  "screenshots": [
    {"id": "en-US/Pixel 9-Home", "status": "changed", "reason": "pixels", "pixels": 62,
     "boxes": [[5, 5, 4, 18], [20, 40, 1, 1], [28, 60, 6, 6]],
     "baseline": "images/baseline/en-US/Pixel 9-Home.png", "new": "images/new/en-US/Pixel 9-Home.png",
     "diff": "images/diff/en-US/Pixel 9-Home.png",
     "platform": "android", "device": "Pixel 9", "language": "en-US", "appearance": "light",
     "preview": "Home", "fontScale": 1}
  ],
  "errors": []
}
```

- `status`: `error` if `errors` is not empty, else `failed` if any changed/added/removed, else
  `passed`. Exit code 2, 1, 0.
- `counts.errors` = length of `errors`.
- `fingerprint`: the run's, as in the report.
- `screenshots`: every listed id, sorted by id. Each has `platform`, `device`, `language`,
  `appearance`, `preview`, `fontScale` or `textSize` (`"default"` when none), and `runtime` (iOS),
  from the report (from `baseline.json` for removed). Present only when they apply: `reason`,
  `pixels`, `boxes`, `baselineSize`, `newSize`, and the image paths (relative to the report
  directory, not URL-encoded): `baseline` (changed, removed), `new` (changed, added), `diff` (changed).

## manifest.json

In the report directory; `accept` checks it against the branch.

```json
{"schema": 1, "commit": "…", "branch": "feature/x", "configHash": "8f36…",
 "fingerprint": {"android": {…}}, "ids": {"added": [], "changed": ["en-US/Pixel 9-Home"], "removed": []}}
```

## junit.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="swiftshot" tests="3" failures="1" errors="1">
  <testcase classname="android.Pixel 9.en-US" name="Home light">
    <failure message="changed: 62 pixels"/>
  </testcase>
  <testcase classname="android.Pixel 9.en-US" name="Settings light 1.3x"/>
  <testcase classname="swiftshot" name="error 1">
    <error message="Broken · Pixel 9 · en-US: boom"/>
  </testcase>
</testsuite>
```

- One `<testcase>` per `screenshots` entry, same order, then one per error (`name="error <n>"`,
  from 1).
- `classname="<platform>.<device>.<language>"`, `name="<preview> <appearance>[ <scale>]"`;
  scale is `<fontScale>x` when not 1 (number as in JSON), or the `textSize` when not `default`.
- Failure messages: `changed: <pixels> pixels`, `changed: size <w>x<h> to <w>x<h>`, `added`,
  `removed`. Unchanged entries are self-closing.
- `tests` = entries + errors, `failures` = changed + added + removed, `errors` = errors.
- Attribute escaping: `&` `<` `>` `"` as `&amp;` `&lt;` `&gt;` `&quot;`; TAB LF CR as `&#9;`
  `&#10;` `&#13;`; other characters below U+0020 dropped. 2-space indent, LF line ends, final `\n`.
