# Contributing

## Bugs

[Open an issue](https://github.com/LukasAnda/swiftshot/issues/new/choose) with `swiftshot --version`,
`xcodebuild -version`, the command you ran and its log (`--verbose`). A screenshot of the wrong
output and the matching preview code help most.

## Pull requests

```
make                                                     # builds bin/
swift test                                               # unit tests
SWIFTSHOT_INTEGRATION=1 swift test --filter IntegrationTests
```

The integration tests render `Example/DemoApp` and compare it pixel by pixel with booted
simulators. They boot simulators, so run them one at a time.

- Keep changes focused; one fix or feature per pull request.
- Pull requests are squash-merged, so the title becomes the commit message: short, imperative,
  e.g. "Render tab bars in landscape".
- Add a test for the change.
- Output must stay pixel identical to `--mode device`.
- `Unit tests` must pass before merging. The integration suite runs on every pull request too.

By contributing you agree that your contribution is licensed under the [AGPL-3.0](LICENSE).
