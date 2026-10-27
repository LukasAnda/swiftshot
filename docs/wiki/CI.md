| | runner | needs |
|---|---|---|
| iOS | a Mac: the free GitHub-hosted `macos-26` and `xcode-27` runners | Xcode and the runtimes you render |
| Android, Compose Multiplatform (Android, desktop) | any Linux or Mac runner, e.g. the free `ubuntu-latest` | a JDK 21+ and the Android SDK your build uses (preinstalled on GitHub's runners) |

Neither boots a simulator or an emulator, and neither needs a GUI session.

## GitHub Actions

```yaml
jobs:
  ios:
    runs-on: xcode-27
    steps:
      - uses: actions/checkout@v7
      - uses: LukasAnda/swiftshot@v0.7.0
        with:
          version: 0.7.0
      - uses: actions/upload-artifact@v7
        with:
          name: ios-screenshots
          path: fastlane/screenshots

  android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v6
        with:
          distribution: temurin
          java-version: 21
          cache: gradle
      - uses: LukasAnda/swiftshot@v0.7.0
        with:
          version: 0.7.0
      - uses: actions/upload-artifact@v7
        with:
          name: android-screenshots
          path: fastlane/metadata/android
```

| input | default | |
|---|---|---|
| `version` | `latest` | swiftshot release to install |
| `args` | | arguments for `swiftshot run`; empty uses `swiftshot.json` |
| `working-directory` | `.` | folder with the project and `swiftshot.json` |

The action runs `install.sh`: on a Linux runner it installs the Android package (Android and
Compose Multiplatform without iOS), on an Apple silicon Mac both platforms. In a Gradle project `swiftshot run` renders Android, see
[[Command line]].

## iOS

Several iOS versions: the runner image ships a few runtimes. Missing ones can be downloaded with
`--download-missing-runtimes` (adds several minutes).

```yaml
      - uses: LukasAnda/swiftshot@v0.7.0
        with:
          args: --ios 26.5,27.1 --download-missing-runtimes
```

Upload to App Store Connect after rendering:

```yaml
      - run: fastlane deliver --skip_binary_upload --skip_metadata --overwrite_screenshots --force
```

## Android

`cache: gradle` in `setup-java` caches Gradle's dependencies and wrapper between runs. Swiftshot's
own cache (unpacked layoutlib, class-data-sharing archives, device art) can be cached too:

```yaml
      - uses: actions/cache@v6
        with:
          path: ~/.cache/swiftshot/android
          key: swiftshot-android-${{ runner.os }}-0.7.0
```

macOS runners work the same way; there the cache is `~/Library/Caches/swiftshot/android`.

Pass Gradle arguments with `args`, for example a module and a variant:

```yaml
      - uses: LukasAnda/swiftshot@v0.7.0
        with:
          args: --modules :app --variant demoDebug --gradle-arg=--no-daemon
```

Upload to Google Play after rendering with `"layout": "fastlane"`:

```yaml
      - run: fastlane supply --skip_upload_apk --skip_upload_aab --skip_upload_metadata --skip_upload_changelogs --skip_upload_images
```

## Device frames on CI

iOS: accept Apple's bezel license with a flag, and cache the downloaded bezels between runs:

```yaml
      - uses: actions/cache@v6
        with:
          path: ~/Library/Caches/swiftshot/frames
          key: swiftshot-frames-1
      - uses: LukasAnda/swiftshot@v0.7.0
        with:
          args: --frame appstore --accept-bezel-license
```

Android: `--frame plain` needs no license prompt. The device art is downloaded from AOSP once
into Swiftshot's cache, which the cache step above keeps.

## Other CI

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | SWIFTSHOT_VERSION=0.7.0 sh
~/.swiftshot/bin/swiftshot run --download-missing-runtimes     # iOS
~/.swiftshot/bin/swiftshot run                                 # Android, in the folder with gradlew
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
