Swiftshot needs a Mac with Xcode and the runtimes you render. It needs no booted simulator and no
GUI session, and runs on the free GitHub-hosted `macos-26` and `xcode-27` runners.

## GitHub Actions

```yaml
jobs:
  screenshots:
    runs-on: xcode-27
    steps:
      - uses: actions/checkout@v4
      - uses: LukasAnda/swiftshot@v0.1.3
        with:
          version: 0.1.3
      - uses: actions/upload-artifact@v4
        with:
          name: screenshots
          path: fastlane/screenshots
```

| input | default | |
|---|---|---|
| `version` | `latest` | swiftshot release to install |
| `args` | | arguments for `swiftshot run`; empty uses `swiftshot.json` |
| `working-directory` | `.` | folder with the project and `swiftshot.json` |

Several iOS versions: the runner image ships a few runtimes. Missing ones can be downloaded with
`--download-missing-runtimes` (adds several minutes).

```yaml
      - uses: LukasAnda/swiftshot@v0.1.3
        with:
          args: --ios 26.5,27.1 --download-missing-runtimes
```

Upload to App Store Connect after rendering:

```yaml
      - run: fastlane deliver --skip_binary_upload --skip_metadata --overwrite_screenshots --force
```

## Device frames on CI

Accept Apple's bezel license with a flag, and cache the downloaded bezels between runs:

```yaml
      - uses: actions/cache@v4
        with:
          path: ~/Library/Caches/swiftshot/frames
          key: swiftshot-frames-v1
      - uses: LukasAnda/swiftshot@v0.2.0
        with:
          args: --frame appstore --accept-bezel-license
```

## Other CI

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=0.1.3 sh
~/.swiftshot/bin/swiftshot run --download-missing-runtimes
```

Publish the output folder as a build artifact. The exit code is non-zero if any screenshot failed.

## Visual review tools

Plain PNGs with stable names work with screenshot review services:

```
npx @argos-ci/cli upload fastlane/screenshots   # Argos, needs ARGOS_TOKEN
npx @percy/cli upload fastlane/screenshots      # Percy, needs PERCY_TOKEN
```

## Booted simulators on CI

Only `--mode device` and `--boot` boot simulators. Then:

- `--device-set <dir>` keeps the simulators away from the machine's own.
- `--template-cache <dir>` holds per-runtime boot templates. Cache it between jobs to skip the first boot.
- On small runners simulators take turns to stay within memory. `SWIFTSHOT_SIMULATORS=<n>` overrides how many run at once.
