## Requirements

| | iOS | Android, desktop, Compose Multiplatform |
|---|---|---|
| machine | Apple silicon Mac | Mac or Linux (Compose Multiplatform iOS targets need a Mac) |
| tools | Xcode 26.6 or 27.x, and the simulator runtimes you render (Xcode > Settings > Components) | JDK 21 or later; the Android SDK only for Android targets |
| project | an app with `#Preview`s, iOS 17 or later | a Gradle project with Compose `@Preview`s and `ui-tooling` on the debug classpath, see [[Android]] |

Nothing has to be added to either project.

## Homebrew (Mac and Linux)

```
brew install lukasanda/tap/swiftshot
```

The formula lives in [LukasAnda/homebrew-tap](https://github.com/LukasAnda/homebrew-tap)
and is updated on every release. On a Mac it installs both platforms: `swiftshot` renders iOS, and
hands over to the Android renderer in a Gradle project. On Linux it installs the Android renderer
and Homebrew's `openjdk@21`.

## Linux

On Linux `swiftshot` renders Android (Jetpack Compose, Wear OS) and the Android and desktop
targets of Compose Multiplatform. iOS targets are skipped. The commands and `swiftshot.json` are
the same as on a Mac.

| | |
|---|---|
| Homebrew | `brew install lukasanda/tap/swiftshot` |
| Debian, Ubuntu | `curl -fsSLO https://github.com/LukasAnda/swiftshot/releases/latest/download/swiftshot_all.deb && sudo apt install ./swiftshot_all.deb` |
| Fedora, RHEL, openSUSE | `sudo dnf install https://github.com/LukasAnda/swiftshot/releases/latest/download/swiftshot.noarch.rpm` |
| any distribution | the [install script](#install-script-mac-and-linux), or `swiftshot-android.tar.gz` from the releases page |

The `.deb` recommends `openjdk-21-jre-headless`, the `.rpm` `java-21-openjdk-headless`; any other
JDK 21+ works too ([JDK](#jdk-android)). Each release also has versioned packages,
`swiftshot_<version>_all.deb` and `swiftshot-<version>-1.noarch.rpm`, each with a `.sha256`.

## Install script (Mac and Linux)

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | sh
export PATH="$HOME/.swiftshot/bin:$PATH"
```

| machine | downloads | installs |
|---|---|---|
| Apple silicon Mac | `swiftshot-macos-arm64.tar.gz` | iOS and Android |
| Linux, Intel Mac | `swiftshot-android.tar.gz` | Android, desktop and Compose Multiplatform (no iOS): a `swiftshot` launcher and its jars |

| variable | default | |
|---|---|---|
| `SWIFTSHOT_VERSION` | latest | release to install, e.g. `0.7.0` |
| `SWIFTSHOT_PREFIX` | `~/.swiftshot` | install location |
| `SWIFTSHOT_ANDROID_ONLY` | | set on an Apple silicon Mac to install the Android package only |

The script downloads from the [releases page](https://github.com/LukasAnda/swiftshot/releases) and
checks the SHA-256.

## JDK (Android)

The Android renderer needs a JDK 21 or later. Android Studio's bundled one, and a Linux
distribution's, are found automatically. The first one that exists and is 21 or later is used:

1. `--java-home` or `"java_home"` in `swiftshot.json`
2. `SWIFTSHOT_JAVA_HOME`
3. `JAVA_HOME`
4. Android Studio's JDK: `/Applications/Android Studio.app`, `~/Applications/Android Studio.app`,
   `/opt/android-studio/jbr`
5. `java` on `PATH`
6. `/usr/lib/jvm/*`, newest first

Without one, `swiftshot` says which package to install.

`--java-home` applies to the renderer processes and the Gradle build (as `JAVA_HOME`); Gradle
otherwise uses your `JAVA_HOME` as usual.

## From source

```
git clone https://github.com/LukasAnda/swiftshot
cd swiftshot
make install         # Mac: iOS and Android, into /usr/local/bin (PREFIX=… to change)
```

`make android` builds only the Android jars and the launcher into `bin/` (any OS with a JDK 21+);
run `bin/swiftshot-android`.

## Check it

```
swiftshot --version    # swiftshot 0.7.0, or "swiftshot 0.7.0 (android)" in a Gradle project
swiftshot devices      # iOS: installed runtimes and devices; in a Gradle project: Android devices
```

## Update

Homebrew: `brew upgrade swiftshot`, uninstall with `brew uninstall swiftshot`.

`.deb` / `.rpm`: install the new package the same way; uninstall with `sudo apt remove swiftshot`
or `sudo dnf remove swiftshot`.

Install script: run it again. To uninstall, delete `~/.swiftshot`.

Caches can be deleted at any time: `~/Library/Caches/swiftshot` on a Mac,
`~/.cache/swiftshot` on Linux.
