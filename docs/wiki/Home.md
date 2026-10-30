<img src="https://raw.githubusercontent.com/LukasAnda/swiftshot/main/docs/assets/logo.svg" width="72" height="72" alt="">

Swiftshot renders screenshots of the previews you already have, for every device, language and
appearance, from one command: for screenshot tests, and as App Store and Google Play screenshots.

- **iOS**: SwiftUI and UIKit `#Preview`s, for every iPhone, iPad and Apple Watch and iOS version,
  without booting a simulator. Apple silicon Mac with Xcode.
- **Android**: Jetpack Compose `@Preview`s, for phones, foldables, tablets and Wear OS, without an
  emulator. Mac or Linux with a JDK 21+.
- **Compose Multiplatform**: shared `@Preview`s for Android, desktop and iOS in one run. Linux
  renders the Android and desktop targets.
- **Flutter**: widget `@Preview`s for iPhones, iPads and Android devices. Mac or Linux; on a Mac
  with Xcode, iOS renders on Flutter's iOS engine, pixel identical to a simulator.

Run `swiftshot` in the project folder: an Xcode project renders iOS, a Gradle project Android, a
`pubspec.yaml` Flutter.

**Start here**

- [[Installation]]: install on a Mac, Linux or a CI machine
- [[Android]]: Jetpack Compose previews for phones, foldables, tablets and Wear OS
- [[Compose Multiplatform]]: Android, desktop and iOS screenshots from shared previews
- [[Flutter]]: widget previews on iPhones, iPads and Android devices
- [[Configuration]]: `swiftshot.json` and per-screenshot settings, for every platform
- [[Command line]]: every command and flag
- [[Screenshot testing]]: record a baseline, verify against it, accept changes
- [[CI]]: GitHub Actions and other CI systems
- [[Device frames]]: Apple bezels, App Store titles and backgrounds, Android Studio's device art
- [[Migrating|Migrating-from-fastlane]]: from `fastlane snapshot` and `screengrab`, Paparazzi and Roborazzi
- [[How it works]]: why it's fast and how output stays pixel identical
- [[Troubleshooting]]
- [[Roadmap]]: what's planned for upcoming versions

**Links**

- [README](https://github.com/LukasAnda/swiftshot#readme)
- [Releases](https://github.com/LukasAnda/swiftshot/releases)
- [GitHub Marketplace](https://github.com/marketplace/actions/swiftshot-preview-screenshots)
- [Report a bug](https://github.com/LukasAnda/swiftshot/issues/new/choose)
