# Contributing

## Bugs

[Open an issue](https://github.com/LukasAnda/swiftshot/issues/new/choose) with `swiftshot --version`,
the toolchain (`xcodebuild -version`, the Android Gradle plugin version or `flutter --version`),
the command you ran and its log (`--verbose`). A screenshot of the wrong output and the matching
preview code help most.

## Pull requests

```
make                                                     # builds bin/
swift test                                               # unit tests
SWIFTSHOT_INTEGRATION=1 swift test --filter IntegrationTests
```

Android, Compose Multiplatform and Flutter live in `Android/` (Kotlin, JDK 21):

```
make android                                             # builds the JVM CLI and workers into bin/
cd Android && ./gradlew :cli:test                        # unit tests
```

The integration tests render `Example/DemoApp` and compare it pixel by pixel with booted
simulators. They boot simulators, so run them one at a time.

- Keep changes focused; one fix or feature per pull request.
- Pull requests are squash-merged, so the title becomes the commit message: short, imperative,
  e.g. "Render tab bars in landscape".
- Add a test for the change.
- Output must stay pixel identical to `--mode device`.
- `Unit tests` must pass before merging. The integration suite runs on every pull request too.

The wiki is published from `docs/wiki` when it changes on main, so edit the pages there.

By contributing you agree that your contribution is licensed under the [AGPL-3.0](LICENSE).
