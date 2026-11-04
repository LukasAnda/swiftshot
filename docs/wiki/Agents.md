How a coding agent adds Swiftshot to a project and keeps its screenshot tests passing. The
previews you already have are the test cases.

## Rules

- **Baselines are recorded and accepted on CI, not on your machine.** Fonts and rendering can
  differ slightly between machines, so a local baseline is marked `local` and may not match CI.
- **A CI never accepts by itself.** A person triggers accept (a comment, a manual job or an
  approval, see the recipes below). Don't run `swiftshot accept` or `swiftshot record` yourself, and
  don't edit the files in `screenshots-baseline`.
- `swiftshot run` and `swiftshot verify` are safe to run locally to see the screens or a diff.

## Install

```
brew install lukasanda/tap/swiftshot
swiftshot --version
```

Other ways (Linux packages, the install script, a CI machine) and the requirements: [[Installation]].
iOS needs an Apple silicon Mac with Xcode; the others need a JDK 21+.

## Set up

In the folder with the `.xcodeproj` or `.xcworkspace` (iOS), `gradlew` (Android, Compose
Multiplatform) or `pubspec.yaml` (Flutter):

```
swiftshot init       # writes swiftshot.json
swiftshot list --json
swiftshot run
```

`init` detects the scheme or modules, languages and devices; it stops if `swiftshot.json` exists
unless `--force` is given. `list` shows which previews were found: if one is missing, see
*Common failures*. `run` writes PNGs and `screenshots.html` to `<output_directory>` (default
`screenshots`; `init` may choose another, e.g. `fastlane/screenshots`). Options: [[Configuration]]
and [[Command line]].

## Previews that render well

Write one preview per screen state worth checking. Load sample data synchronously: images and
animations that are not finished when the screenshot is taken give unstable results (`--delay
<seconds>` waits longer).

| platform | what to write |
|---|---|
| SwiftUI, UIKit | `#Preview` with a SwiftUI view, a `UIViewController` or a `UIView`. Build the Debug configuration: Release builds leave `#Preview` out. `.sizeThatFitsLayout` and `.fixedLayout(width:height:)` render a component at its own size. Sheets and alerts shown by the preview are captured. |
| Compose (Android) | `@Preview` with `showSystemUi = true` for a whole screen, without it for a component. `androidx.compose.ui:ui-tooling` must be on the debug classpath (`debugImplementation`). Multipreviews and `@PreviewParameter` work; a preview's own `device`, `locale`, `uiMode` and `fontScale` win over the matrix. See [[Android]]. |
| Compose Multiplatform | `@Preview` (`androidx.compose.ui.tooling.preview.Preview`) in `commonMain`; one run renders the Android, desktop and iOS targets the module has. See [[Compose Multiplatform]]. |
| Flutter | `@Preview` on a public top-level function, static method or widget constructor, in `lib/`. `size` makes a component, without it the preview fills the screen. Private ones are skipped with a warning. See [[Flutter]]. |

## Verify

```
swiftshot verify --json > result.json
```

Stdout is the `result.json` of this run and nothing else; logs go to stderr. Exit 2 can also come
with empty stdout and no `result.json` (a malformed `swiftshot-report.json`, a failed PNG copy; the
error is on stderr): check that stdout is not empty before parsing it. `--json` also works
with `list` and `devices`, see [[Command line]]. The files `verify` writes are in
`<output_directory>-report`: [[Baseline format]] describes every field.

## Read result.json

- `status`: `passed`, `failed` (differences) or `error`. The exit code is 0, 1 or 2.
- `counts`: `unchanged`, `changed`, `added`, `removed`, `errors`.
- `screenshots`: one entry per screenshot; its keys are sorted, so read `id` and `status` by name.
  For every status other than `unchanged`, look at it:
  - `changed`: `reason` and `pixels`, `boxes` (where it differs, `[x, y, w, h]`), and the images
    `baseline`, `new` and `diff`, as paths inside `<output_directory>-report`.
  - `added`, `removed`: the preview has no baseline yet, or its baseline has no preview.
  - `error`: `message` says what failed.
- `errors`: render errors, with the `id` they belong to when known.
- `fingerprintMismatch`: the baseline was made by a different renderer or host; differences may
  come from that.

A change you made on purpose is for a person to accept; a change you didn't is a bug to fix.

The same folder has `index.html`, the report for a person to review. Point them at it instead of
summarising images you can't compare.

## Accept

After a person has looked at the report, accepting happens on CI: for example the comment
`/swiftshot accept` on a pull request (GitHub), or the manual job `swiftshot-accept` (GitLab). The
recipes are listed below. Don't try to accept from your own machine.

The first baseline is made the same way: with no baseline yet, `verify` on CI reports every
screenshot as `added` (exit 1), and a person accepts that report. The accept commits the PNGs and
`baseline.json` with its fingerprints.

## Exit codes

| command | 0 | 1 | 2 | 64 |
|---|---|---|---|---|
| `run` | every screenshot rendered | a screenshot or the build failed, or a wrong option | | |
| `list`, `devices` | done | failed (the build failed, wrong option) | | |
| `init` | `swiftshot.json` written | failed, or `swiftshot.json` exists and no `--force` | | |
| `verify` | no differences | differences | errors | usage error |
| `record` | recorded | | errors, or nothing rendered | usage error |
| `accept` | applied, or nothing to apply | refused (report is not from this commit, push failed) | interrupted | usage error, or not a valid report |
| `frame`, `calibrate`, `emit-table` (iOS tool) | done | failed | | |

`--json` on any command other than `list`, `devices` and `verify` is a usage error. On the iOS
tool every command exits 64 for such a flag (and for `--from` and the like); the Android tool
exits 1 for it, except `record` and `accept`, which exit 64. Details: [[Command line]],
[[Baseline format]].

## Common failures

| message or symptom | fix |
|---|---|
| no previews found (iOS) | build the Debug configuration; `#Preview` is left out of Release. `swiftshot list` shows what was found. |
| `No @Preview functions found in …` | the module compiled no `@Preview` in that variant; check `--modules` and `--variant`. |
| `… has no androidx.compose.ui:ui-tooling on its debug classpath` | add `debugImplementation("androidx.compose.ui:ui-tooling")`. |
| `swiftshot needs a JDK 21 or later` | install a JDK 21+, or set `JAVA_HOME`, `SWIFTSHOT_JAVA_HOME` or `--java-home`. |
| iOS renders instead of Android | pass `--platform android` or `--project-dir` to the Gradle project. |
| a runtime or device is missing (iOS) | `swiftshot devices` lists the devices from `--devices`, the config or the defaults, and the installed runtimes; an unknown name exits 1 with `Unknown device`; `--download-missing-runtimes`, or `--allow-unsupported-devices`. |
| unfinished images or animations | load sample data synchronously, or `--delay <seconds>`. |
| a long list is cut off | `--full-length`, or `"full_length": true` for that screen. |
| `verify` exits 2 | read `errors` and the entries with `status` `error` in `result.json`. |
| `verify` exits 1 with `fingerprintMismatch` | the renderer or host differs from the one that made the baseline; compare on CI. |
| `accept` refuses | the report is from an older commit; run `verify` again. |

More: [[Troubleshooting]].

## CI

[[CI]] lists what each system shows and how a person accepts. The recipes:

- [[GitHub Actions|CI-GitHub-Actions]]
- [[GitLab|CI-GitLab]]
- [[Bitbucket|CI-Bitbucket]]
- [[Bitrise|CI-Bitrise]]
- [[Codemagic|CI-Codemagic]]
- [[CircleCI|CI-CircleCI]]
- [[Azure Pipelines|CI-Azure-Pipelines]]
- [[Jenkins|CI-Jenkins]]

## For your AGENTS.md

````
## Screenshot tests (Swiftshot)
- Previews are the test cases. Add a public preview per screen state, with sample data loaded
  synchronously; iOS builds must be Debug.
- See the screens: `swiftshot run`. Compare: `swiftshot verify --json > result.json`
  (exit 0 same, 1 differences, 2 errors, 64 usage error). With exit 2, stdout can be empty (the
  error is on stderr): don't parse an empty `result.json`.
- Read result.json: `status`, `counts`, and every entry of `screenshots` whose `status` is not
  `unchanged` (`changed` has `diff`, `boxes`, `pixels`; `error` has `message`).
- Fix unintended differences. Never run `swiftshot record` or `swiftshot accept` locally and never
  edit `screenshots-baseline/`: baselines are recorded and accepted on CI, and a person triggers
  the accept. Tell the person which ids changed on purpose.
- Docs: https://github.com/LukasAnda/swiftshot/wiki/Agents
````
