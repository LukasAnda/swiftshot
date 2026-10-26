What's planned, in rough order. Nothing here has a date yet.
[Open a feature request](https://github.com/LukasAnda/swiftshot/issues/new?template=feature_request.yml)
to suggest something or to say what you need most.

## Homebrew

`brew install swiftshot`, with updates through `brew upgrade`. The GitHub Action and the install
script stay.

## Android: Jetpack Compose

Screenshots of `@Preview` composables for every device, locale, font scale and dark mode, from
one command, with the same output layout and gallery. The goal is to be faster than Paparazzi and
Roborazzi, measured the same way as the fastlane comparison: same previews, same machine, public
workflow.

## Compose Multiplatform

Shared composables rendered for iOS and Android from one configuration, so a multiplatform app
gets App Store and Play Store screenshots in one run.

## Flutter

Screenshots of Flutter widgets on iOS and Android devices, with the same matrix of devices,
languages, text sizes and appearances.

## IDE plugins

See screenshots while you edit, without leaving the IDE:

- Xcode
- Android Studio and IntelliJ IDEA

Each change re-renders only the previews it affects, across the devices and languages you
choose.
