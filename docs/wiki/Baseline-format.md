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

`accept`: 0 applied (or nothing to apply), 1 refused (the report's commit isn't HEAD and a commit
other than an `accept` commit followed it, or `git push` failed), 64 usage error or invalid report
(also: an `--only` id the reports don't list, the same id with different content in two reports, a
zip entry leaving the report or a symbolic link, a damaged zip, a `--from` that can't be read, a
malformed manifest.json, result.json or baseline.json). Interrupted: 1.

## Serialization

**JSON** (every file on this page):

- Keys sorted by their UTF-8 bytes.
- Pretty: 2-space indent, `"key": value`, one element per line, every non-empty array and
  object expanded (also `[x, y, w, h]` boxes), empty ones as `[]` and `{}`, a final `\n`.
  Compact (used for hashes only): the same with no whitespace at all.
- Strings: escape `"` `\` as `\"` `\\`, LF CR TAB as `\n` `\r` `\t`, other characters below
  U+0020 as `\u00xx` (lowercase hex). Nothing else is escaped (not `/`, not non-ASCII).
- Numbers: an integral value is written as an integer (`1.0` → `1`); others in the shortest
  decimal form that round-trips, never with an exponent (`2.625`, `1.3`). Magnitudes of 1e15 and
  above don't occur in these files (implementations may reject them).
- Arrays of ids or messages are sorted by UTF-8 bytes unless stated otherwise.

**Hash**: lowercase hex SHA-256 of the compact JSON's UTF-8 bytes.

**PNG** (diff images; baseline and new images are byte copies): 8-bit RGBA (colour type 6),
interlace 0, filter type 0 on every row, chunks `IHDR`, one `IDAT`, `IEND` and nothing else. The
`IDAT` is one zlib stream: deflate level 6, window 15, memory level 8, default strategy, as zlib's
`compress2(…, 6)` and Java's `new Deflater(6)` + `finish()` write it (verified identical with zlib
1.2.12). Implementations must use zlib (madler) with these defaults, not zlib-ng.

**Decoding** (for comparison): bit depth 8, colour type 6 (RGBA) or 2 (RGB, alpha 255), any filter,
interlace 0; other chunk types ignored. Samples are used as stored: no colour management, no
premultiplication. Strict: a bad signature, a truncated chunk, a CRC mismatch, `IHDR` missing or
not first, a zlib error, decompressed data of the wrong length or a filter byte above 4 is
malformed. Any other or malformed PNG is the error `unsupported PNG` for that id.

**Determinism**: `commit`, `branch`, `version` and `ci` come from `SWIFTSHOT_COMMIT`,
`SWIFTSHOT_BRANCH`, `SWIFTSHOT_VERSION_OVERRIDE` and `SWIFTSHOT_CI` (`true`/`false`) when set (tests
set them: `0123456789abcdef0123456789abcdef01234567`, `feature/x`, `1.0.0-test`, `false`).
Otherwise from git/CI detection and the binary; an unknown commit or branch is `null`. The host is
detected once per run (`SWIFTSHOT_HOST` overrides it) and written into every fingerprint of
that run.

## swiftshot-report.json additions

The run report keeps its current keys and gains:

- `fingerprint`: platform → fingerprint (below), one per platform the run rendered.
- `scope`: what the run covered.
  ```json
  {"platforms": ["android", "ios"], "modules": [":app"], "runtimes": ["26.0"],
   "devices": ["iPhone 17 Pro", "Pixel 9"], "languages": ["en-US"], "appearances": ["dark", "light"],
   "textSizes": ["default"], "fontScales": [1, 1.3], "previews": ["Home", "Settings"],
   "previewFilter": ["Home*"]}
  ```
  Each list is the **requested matrix ∪ the values actually rendered**. Requested: the platforms,
  Gradle modules (Android, desktop), devices, languages, appearances, font scales / text sizes and
  iOS runtime versions the run selected, from flags, the config's global lists and every value
  named in a `screens` rule (resolved: `"ios_versions": ["26"]` → the installed `26.x` versions).
  A selected value counts even when it rendered nothing (a module with no previews, a device only
  a deleted preview used). `modules` and `runtimes` are always present, `[]` when they don't
  apply. `textSizes` when iOS was in the run (`"default"` = the device's own), `fontScales` when
  Android, desktop or Flutter was. `previews`: the preview names the run found after filters
  (informational). `previewFilter`: the `--previews` globs, `[]` when none. All lists sorted
  (`fontScales` by value).
- Per screenshot: `id`, `platform` (`ios`, `android`, `desktop`, `flutter`) and `scale` (pixels per
  point/dp, e.g. `3`, `2.625`). Existing per-screenshot keys used here: `preview`, `device`,
  `language`, `appearance`, `module` (Android, desktop), `fontScale` (Android, desktop, Flutter),
  `textSize` (iOS, absent = `"default"`), `runtime` (iOS).
- `errors` become objects: `{"id": "<id>", "message": "…"}`, the id being the one the failed shot
  would have had. An error the run can't tie to a shot (e.g. a module that doesn't compile) has
  no `id`. Several errors for one id: the first in report order counts, the rest are ignored.

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
| `layoutlib`, `compose`, `jdk` | android | versions from the resolved classpath |
| `skiko`, `compose`, `jdk` | desktop | versions from the resolved classpath |
| `flutter`, `renderer`, `fonts` | flutter | version; `impeller`, `skia` or `exact-ios`; sorted font file names |

Values are strings, `fonts` an array of strings. One run, one host: all platform fingerprints of a
run carry the same `host` (a run with iOS is on macOS). **Fingerprint id**: the first 12 hex digits of the
fingerprint's hash.

**Pixel-relevant**: every field, except `swiftshot` compares only its first two `.`-separated parts
(`1.0.3` = `1.0.0-test`), and `host` is ignored when this run's renderer is the exact iOS one: the
run's fingerprint has `platform` `ios` or `renderer` `exact-ios`. A field present on one side only
is a difference (the other shown as `none`).

## baseline.json

```json
{
  "schema": 1,
  "fingerprints": {"d2d5c0db8687": {"host": "macos-arm64", "mode": "no-boot", "platform": "ios", …}},
  "images": {
    "en-US/iPhone 17 Pro-Home": {"fingerprint": "d2d5c0db8687", "platform": "ios", "device": "iPhone 17 Pro",
      "language": "en-US", "appearance": "light", "preview": "Home", "textSize": "default", "runtime": "26.0", "local": false},
    "en-US/Pixel 9-Home": {"fingerprint": "7d572793275d", "platform": "android", "module": ":app",
      "device": "Pixel 9", "language": "en-US", "appearance": "light", "preview": "Home", "fontScale": 1,
      "local": false}
  }
}
```

- Every image references one entry of `fingerprints`; unreferenced fingerprints are dropped on write.
- iOS images have `textSize` (`"default"` when none) and `runtime`; Android and desktop `module`
  and `fontScale`; Flutter `fontScale`.
- `local`: `true` when the image was rendered outside CI (`record` on a developer machine;
  `accept` writes `local = !ci` from the manifest).

The baseline set is `images`. A PNG under the baseline directory with no `images` entry is
**stray**: it can't be scope-checked, so it is an error only when its id is in this run's output
(below) or has a render error (then the render error is its entry); otherwise it is ignored and
counted in `strayBaselineFiles`. So `strayBaselineFiles` = stray PNGs whose id is not listed. The stray scan runs whether
or not the run has errors.

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

**Ids**: the report's `screenshots`, the report's `errors` with an `id`, baseline.json `images`, and
stray PNGs whose id is in `screenshots`. For each id, in this order:

1. **Leave out** (not listed, not counted, no fingerprint or `local` check): not in `screenshots`,
   no render error, and the baseline image is out of scope or the run has an error without `id`
   (such a run can't tell which shots it lost, so it reports no removals).
2. **`error`**, the first that applies:
   1. render error (report `errors`) → its message
   2. in `screenshots`, no output PNG → `output image missing`
   3. in `images`, no baseline PNG → `baseline image missing`
   4. stray baseline PNG → `baseline image not in baseline.json`
   5. both PNGs present, bytes differ, either not decodable as below → `unsupported PNG`
3. **`removed`**: not in `screenshots`. **`added`**: not in `images`.
4. **`unchanged`**: the PNG bytes are equal (checked before decoding, so equal files are never
   decoded and never `unsupported`).
5. Otherwise compare (below): `unchanged` or `changed`.

`error` is never `removed`, and `accept` never deletes the baseline image of an `error` id.

**In scope**: `platform` ∈ `platforms`, `device` ∈ `devices`, `language` ∈ `languages`,
`appearance` ∈ `appearances`; `module` ∈ `modules`, `runtime` ∈ `runtimes`, `textSize` ∈
`textSizes`, `fontScale` ∈ `fontScales`, each if the image has that key; and `previewFilter` is
empty or one of its globs matches `preview`. A list missing from the scope matches nothing.
Strings compare exactly; `fontScale` compares as a decimal value (`1` = `1.0`, `1.3` = `1.30`).

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

**Errors**: `errors` holds `{"id", "message"}` for every `error` entry (sorted by id), then the
report's errors without `id` as `{"message"}`, in report order.

**Fingerprint mismatch**: for every distinct baseline fingerprint referenced by the `images` entry
of a listed id (any status, `error` included), compare it with the run's fingerprint for its platform (none: skipped).
Each pixel-relevant difference is a message `<platform> <field>: baseline <value>, this run <value>`
(arrays joined with `, `, absent = `none`); duplicates dropped, sorted. `verify` prints these
first; they never change the status.

**localBaseline**: `true` when the `images` entry of a listed id (any status, `error` included) has
`local: true`. A warning, never a failure.

## result.json

```json
{
  "schema": 1,
  "status": "failed",
  "counts": {"added": 0, "changed": 1, "errors": 0, "removed": 0, "unchanged": 1},
  "commit": "0123456789abcdef0123456789abcdef01234567",
  "branch": "feature/x",
  "version": "1.0.0-test",
  "ci": false,
  "host": "linux-x64",
  "fingerprint": {"android": {…}},
  "fingerprintMismatch": [],
  "localBaseline": false,
  "screenshots": [
    {"id": "en-US/Pixel 9-Home", "status": "changed", "reason": "pixels", "pixels": 62,
     "boxes": [[5, 5, 4, 18], [20, 40, 1, 1], [28, 60, 6, 6]],
     "baseline": "images/baseline/en-US/Pixel 9-Home.png", "new": "images/new/en-US/Pixel 9-Home.png",
     "diff": "images/diff/en-US/Pixel 9-Home.png",
     "platform": "android", "module": ":app", "device": "Pixel 9", "language": "en-US",
     "appearance": "light", "preview": "Home", "fontScale": 1},
    {"id": "en-US/Pixel 9-Broken", "status": "error", "message": "IllegalStateException: boom", …}
  ],
  "errors": [{"id": "en-US/Pixel 9-Broken", "message": "IllegalStateException: boom"}],
  "strayBaselineFiles": 0
}
```

- `status`: `error` if `errors` is not empty, else `failed` if any changed/added/removed, else
  `passed`. Exit code 2, 1, 0.
- `counts.errors` = length of `errors` (`error` entries plus errors without id).
- `ci`: whether this run was on CI (`SWIFTSHOT_CI` overrides detection). `host`: this run's host,
  the same value as `host` in each of its fingerprints; `null` when the run fingerprint is empty. The detected CI
  vendor and git host are added later as new keys; readers must ignore unknown keys.
- `fingerprint`: the run's, as in the report.
- `strayBaselineFiles`: stray baseline PNGs whose id is not listed in `screenshots`.
- `screenshots`: every listed id, sorted by id (UTF-8 bytes). Each has `platform`, `device`,
  `language`, `appearance`, `preview`, `fontScale` or `textSize` (`"default"` when none), `module`
  (Android, desktop) and `runtime` (iOS): every one the report's screenshot entry provides,
  otherwise from the `images` entry (removed, and `error` ids not in `screenshots`); an `error` id
  in neither has only `id`, `status`, `message`. Present only when they apply: `message` (error),
  `reason`,
  `pixels`, `boxes`, `baselineSize`, `newSize`, and the image paths (relative to the report
  directory, not URL-encoded): `baseline` (changed, removed), `new` (changed, added), `diff` (changed).

## manifest.json

In the report directory; `accept` checks it against the branch. `ci`: whether the verify run was
on CI; `accept` writes `local = !ci` into the images it applies. `accept` only touches the ids
listed here, so a baseline image of an `error` id is never deleted.

```json
{"schema": 1, "commit": "…", "branch": "feature/x", "ci": true, "configHash": "8f36…",
 "fingerprint": {"android": {…}}, "ids": {"added": [], "changed": ["en-US/Pixel 9-Home"], "removed": []}}
```

## accept

`swiftshot accept --from <report> [--from <report>…] [--only <ids>] [--push] [--author "Name <email>"]`
renders nothing. `--from` is a report directory, a zip of one (the report at its root or in its only
top-level directory), or an `http(s)` URL of such a zip (sent `Authorization: Bearer
$SWIFTSHOT_ARTIFACT_TOKEN` when set, only to that host). Zips: no entry may leave the target
directory or be a symbolic link, at most 2 GB extracted.

- For each `changed` and `added` id of `manifest.json`: `images/new/<id>.png` is copied into the
  baseline; its `images` entry is the report's `result.json` screenshot entry (the fields of the
  baseline.json example), `fingerprint` the id of the manifest's fingerprint for its platform,
  `local` = `!ci`. Each `removed` id: its PNG and entry are deleted. Nothing else changes;
  unreferenced fingerprints are dropped and baseline.json is rewritten canonically.
- `--only` (comma-separated, repeatable) restricts to those ids.
- Stale: each report's `commit` must be HEAD, or every commit after it up to HEAD must carry the
  trailer `Swiftshot-Accept: <commit>` (any value), which `accept --push` writes.
- baseline.json is written last (temp file, then rename).
- `--push`: one commit of only the files accept wrote or deleted (other edits in the baseline
  directory stay uncommitted), subject `Update screenshot baseline (3
  changed, 1 added)` (non-zero parts of changed, added, removed), a `Swiftshot-Accept: <commit>`
  trailer per report commit, author and committer `swiftshot <swiftshot@users.noreply.github.com>`
  unless `--author`; then `git push` to the branch's upstream, else `origin HEAD`, never forced.
  Nothing to apply, or none of those files changed: no commit.

## junit.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="swiftshot" tests="4" failures="1" errors="2">
  <testcase classname="android.Pixel 9.en-US" name="en-US/Pixel 9-Broken">
    <error message="IllegalStateException: boom"/>
  </testcase>
  <testcase classname="android.Pixel 9.en-US" name="en-US/Pixel 9-Home">
    <failure message="changed: 62 pixels"/>
  </testcase>
  <testcase classname="android.Pixel 9.en-US" name="en-US/Pixel 9-Settings-1.3x"/>
  <testcase classname="swiftshot" name="error 1">
    <error message=":feature: compilation failed"/>
  </testcase>
</testsuite>
```

- One `<testcase>` per `screenshots` entry, same order, then one per error without id
  (`name="error <n>"`, from 1).
- `classname="<platform>.<device>.<language>"` (`swiftshot` for an `error` id without those
  fields), `name="<id>"`.
- `<failure message=…/>`: `changed: <pixels> pixels`, `changed: size <w>x<h> to <w>x<h>`, `added`,
  `removed`. `<error message="<message>"/>` for errors. Unchanged entries are self-closing.
- `tests` = entries + errors without id, `failures` = changed + added + removed, `errors` =
  `counts.errors`.
- Attribute escaping: `&` `<` `>` `"` as `&amp;` `&lt;` `&gt;` `&quot;`; TAB LF CR as `&#9;`
  `&#10;` `&#13;`; other characters below U+0020 dropped. 2-space indent, LF line ends, final `\n`.
