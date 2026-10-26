Run with `--verbose` for the full log. `swiftshot-report.json` in the output folder lists every
screenshot, timings and errors.

**No previews found.** Build with the Debug configuration; `#Preview` code is left out of Release
builds. `swiftshot list` prints what was found.

**A runtime isn't installed.** Install it in Xcode > Settings > Components, or pass
`--download-missing-runtimes`. `swiftshot devices` lists what's installed.

**A device is skipped.** Each runtime supports only some devices. Pick a runtime that supports it,
or pass `--allow-unsupported-devices` to render it anyway (best effort).

**Images or animations are not finished.** Load sample data synchronously in the preview, or pass
`--delay <seconds>` (per screen: `delay`).

**A long list is cut off.** Use `--full-length` or `"full_length": true` for that screen.

**The watch app isn't rendered.** Add a watch model to `devices` and set `watch_scheme` if the
watch app has its own scheme.

**A launch times out.** The default limit is 600 s; raise it with `--timeout`.

**Something else.** [Open an issue](https://github.com/LukasAnda/swiftshot/issues/new/choose)
with `swiftshot --version`, `xcodebuild -version`, the command and the log.
