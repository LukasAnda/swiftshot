Run with `--verbose` for the full log. `swiftshot-report.json` in the output folder lists every
screenshot, timings and errors.

## iOS

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

## Android

**No JDK 21.** `swiftshot needs a JDK 21 or later` (from the launcher) or `Swiftshot needs JDK 21
or later to render Android previews`: install one (`openjdk-21-jre-headless` on Debian and Ubuntu,
`java-21-openjdk-headless` on Fedora), or set `JAVA_HOME`, `SWIFTSHOT_JAVA_HOME` or `--java-home`.
Android Studio's JDK and the ones in `/usr/lib/jvm` are found automatically. The lookup order is
on [[Installation]].

**ui-tooling missing.** `:app has no androidx.compose.ui:ui-tooling on its debug classpath; add
debugImplementation("androidx.compose.ui:ui-tooling") as Android Studio's previews need it too.`
Add that line to the module's dependencies. With `--variant`, the dependency must be on that
variant's classpath.

**iOS runs instead of Android.** A folder with an `.xcodeproj` or `.xcworkspace`, or a
`swiftshot.json` with `project`, `workspace` or `scheme`, is an iOS project. Pass
`--platform android`, or `--project-dir` to point at the Gradle project.

**iOS needs a Mac.** `iOS needs a Mac with Xcode` on Linux: `--platform ios`, a folder with an
Xcode project, `swiftshot frame`, `calibrate` and `emit-table` need the Mac tool. In a Compose
Multiplatform project the iOS targets are skipped and the rest renders.

**A note about iOS keys.** `swiftshot.json: scheme, mode are for iOS on a Mac; ignored here`: the
file is shared with the iOS tool. Nothing to fix.

**Gradle failed.** `Gradle failed (exit <n>)` is followed by the last 40 lines of Gradle's
output; `--verbose` shows all of it. Run `./gradlew assembleDebug` to see whether the project
builds on its own. Pass extra Gradle arguments with `--gradle-arg` (repeatable) or `gradle_args`.
`Could not resolve app.cash.paparazzi:paparazzi` or `com.android.tools.layoutlib`: add
`mavenCentral()` to the project's repositories.

**Configuration cache.** Swiftshot keeps the project's configuration cache: its init script stays
at one path in the cache folder and its task holds no reference to the project. If Gradle still
reports configuration cache problems, run with `--gradle-arg=--no-configuration-cache` and open an
issue.

**No previews found.** `No @Preview functions found in …`: the module compiled no `@Preview`
functions in that variant. `swiftshot list` prints what was found, per module.

**Unknown device.** `` Unknown device "…". `swiftshot devices` lists them. `` Use a name or id from
`swiftshot devices`, or a `*` glob. `<preview>: unknown device "…"` means a `@Preview(device = …)`
that isn't in Android Studio's catalog; use `Devices.*`, `id:…` or `spec:…`.

**Not framed.** `No device art for pixel_9 (…)`: the device art could not be found locally or
downloaded from AOSP. Install Android Studio, or run once with network access so it lands in the
cache; offline CI can restore the cache folder ([[CI]]). Devices without art stay unframed.

**Wear OS renders dark only.** Wear OS has no light mode, so watch screens render once, dark,
with no appearance suffix. A preview's own `uiMode` still wins.

**`apiLevel` is ignored.** Every preview renders with layoutlib's Android version.

**A long list is cut off.** Use `--full-length` or `"full_length": true` for that screen. It grows
the screen while Compose reports more to scroll (`verticalScroll`, `LazyColumn`).

**Animations or images are not finished.** `--delay <seconds>` advances the preview's clock before
capture. Load sample data synchronously in the preview.

## Something else

[Open an issue](https://github.com/LukasAnda/swiftshot/issues/new/choose) with `swiftshot
--version`, the command and the log, and `xcodebuild -version` (iOS) or `./gradlew --version`
(Android).
