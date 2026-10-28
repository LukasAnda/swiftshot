What's planned for upcoming versions. Version numbers are targets and can move. Each version has a
[milestone](https://github.com/LukasAnda/swiftshot/milestone) that tracks its work.
[Open a feature request](https://github.com/LukasAnda/swiftshot/issues/new?template=feature_request.yml)
to suggest something or to say what you need most.

| version | | status |
|---|---|---|
| [v0.3.0](https://github.com/LukasAnda/swiftshot/releases/tag/v0.3.0) | [Homebrew](#v030--homebrew) | released |
| [v0.4.0](https://github.com/LukasAnda/swiftshot/releases/tag/v0.4.0) | [Android: Jetpack Compose](#v040--android-jetpack-compose) | released |
| [v0.5.0](https://github.com/LukasAnda/swiftshot/releases/tag/v0.5.0) | [Compose Multiplatform](#v050--compose-multiplatform) | released |
| [v0.6.0](https://github.com/LukasAnda/swiftshot/releases/tag/v0.6.0) | [Linux as a full host](#v060--linux-as-a-full-host) | released |
| [v0.7.0](https://github.com/LukasAnda/swiftshot/releases/tag/v0.7.0) | [Flutter](#v070--flutter) | released |
| [v0.8.0](https://github.com/LukasAnda/swiftshot/milestone/7) | [Migration from Paparazzi and Roborazzi](#v080--migration-from-paparazzi-and-roborazzi) | planned |
| [v0.9.0](https://github.com/LukasAnda/swiftshot/milestone/5) | [IDE plugins](#v090--ide-plugins) | planned |

## v0.3.0 · Homebrew

`brew install lukasanda/tap/swiftshot`, with updates through `brew upgrade`. The formula is
in [LukasAnda/homebrew-tap](https://github.com/LukasAnda/homebrew-tap) and every release
updates it. The GitHub Action and the install script stay.

## v0.4.0 · Android: Jetpack Compose

Screenshots of `@Preview` composables for phones, foldables, tablets and Wear OS, every locale,
font scale and dark mode, from one command, on a Mac or Linux. See [[Android]].

## v0.5.0 · Compose Multiplatform

Shared `@Preview`s rendered for Android, desktop and iOS from one configuration, so a
multiplatform app gets Play Store, desktop and App Store screenshots in one run. See
[[Compose Multiplatform]].

## v0.6.0 · Linux as a full host

The same `swiftshot` command, `swiftshot init` and configuration on Linux as on a Mac, for
Android and the Android and desktop targets of Compose Multiplatform; iOS targets are skipped.
Installs with Homebrew, a `.deb` or an `.rpm`. See [[Installation]].

## v0.7.0 · Flutter

Flutter widget `@Preview`s on iPhones, iPads and Android devices, every language and appearance,
on a Mac or Linux. On a Mac with Xcode, iOS renders on Flutter's iOS engine, pixel identical to a
booted simulator. See [[Flutter]].

## v0.8.0 · Migration from Paparazzi and Roborazzi

`swiftshot init` finds Paparazzi and Roborazzi setups (plugins, test rules, recorded snapshot
folders) and sets Swiftshot up to match.

## v0.9.0 · IDE plugins

See screenshots while you edit, without leaving the IDE:

- Xcode
- Android Studio and IntelliJ IDEA

Each change re-renders only the previews it affects, across the devices and languages you
choose.
