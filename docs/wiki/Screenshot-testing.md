Swiftshot can check that your screens still look the way they did. It keeps a **baseline**: a
folder of approved screenshots in your repository. Every run is compared with it, pixel by pixel.

Works for iOS, Android, Compose Multiplatform and Flutter, with the same commands.

## Three commands

```
swiftshot record                       # render and save the screenshots as the baseline
swiftshot verify                       # render and compare with the baseline
swiftshot accept --from <report>       # take the changes verify found into the baseline
```

`record` and `verify` take the same options as `swiftshot run` (devices, languages, `--previews`…).
`accept` renders nothing and takes its own: `--from`, `--only`, `--push`, `--author` (see
[[Command line]]).

1. **Record** once, and commit the `screenshots-baseline` folder.
2. **Verify** after every change. It renders, compares and prints what changed:
   ```
   changed  en-US/iPhone 17 Pro-Welcome  (5320 pixels)
   ! Verify failed: 9 unchanged, 1 changed, 0 added, 0 removed, 0 errors → screenshots-report
   ```
   For each changed screenshot, `screenshots-report/images` holds the old one (`baseline`), the
   new one (`new`) and the difference in red (`diff`).
3. If the change is intended, **accept** it: `swiftshot accept --from screenshots-report`. It
   renders nothing; it copies the new screenshots into the baseline. Commit the result.

`accept` only takes a report made on the commit you are on. If you committed something else
since, run `verify` again first.

A baseline recorded on your own machine is marked as local, and `verify` reminds you of it. Fonts
and rendering can differ slightly between machines, so the baseline is best recorded where verify
runs. CI support for this is coming next.

## Exit codes

| | `verify` | `record` | `accept` |
|---|---|---|---|
| 0 | no differences | recorded | applied, or nothing to apply |
| 1 | differences | | refused (the report isn't from this commit) |
| 2 | errors (a screen failed to render, a file is missing) | errors (screens that failed keep their baseline), or nothing rendered | |
| 64 | wrong option or config | wrong option or config | wrong option, or not a valid report |

## Where files go

```
screenshots/               what this run rendered (output_directory)
screenshots-baseline/      the approved screenshots and baseline.json: commit this
screenshots-report/        what verify found: result.json, junit.xml, images/
```

Change them with `baseline_directory` and `report_directory` in [[Configuration]], or
`--baseline-directory` and `--report-directory`. A screenshot's id is its path in the folder
without `.png`, e.g. `de-DE/iPhone 17 Pro-Welcome-dark`.

## Small differences

By default every pixel must match (with `--mode device`, a booted simulator, a channel may differ
by 1). To allow more:

```json
{
  "tolerance": {"pixels": 10, "max_channel_delta": 2},
  "screens": [
    {"preview": "Clock*", "ignore_regions": [[0, 0, 120, 44]]}
  ]
}
```

- `pixels`: this many pixels may differ.
- `max_channel_delta`: a pixel counts as different only when a colour channel differs by more
  than this (0–255).
- `ignore_regions`: `[x, y, width, height]` in points (iOS) or dp (Android) that are never
  compared.

Only plain PNG screenshots are compared: no device frames, no JPEG. The file formats are in
[[Baseline format]].
