## Requirements

| | iOS | Android |
|---|---|---|
| machine | Apple silicon Mac | Mac or Linux |
| tools | Xcode 26.6 or 27.x, and the simulator runtimes you render (Xcode > Settings > Components) | JDK 21 or later |
| project | an app with `#Preview`s, iOS 17 or later | a Gradle project with Compose `@Preview`s and `ui-tooling` on the debug classpath, see [[Android]] |

Nothing has to be added to either project.

## Homebrew (Mac)

```
brew install lukasanda/tap/swiftshot
```

The formula lives in [LukasAnda/homebrew-tap](https://github.com/LukasAnda/homebrew-tap)
and is updated on every release. It installs both platforms: `swiftshot` renders iOS, and hands
over to the Android renderer in a Gradle project.

## Install script (Mac and Linux)

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | sh
export PATH="$HOME/.swiftshot/bin:$PATH"
```

| machine | downloads | installs |
|---|---|---|
| Apple silicon Mac | `swiftshot-macos-arm64.tar.gz` | iOS and Android |
| Linux, Intel Mac | `swiftshot-android.tar.gz` | Android only: a `swiftshot` launcher and two jars |

| variable | default | |
|---|---|---|
| `SWIFTSHOT_VERSION` | latest | release to install, e.g. `0.4.0` |
| `SWIFTSHOT_PREFIX` | `~/.swiftshot` | install location |
| `SWIFTSHOT_ANDROID_ONLY` | | set on an Apple silicon Mac to install the Android package only |

The script downloads from the [releases page](https://github.com/LukasAnda/swiftshot/releases) and
checks the SHA-256.

## JDK (Android)

The Android renderer needs a JDK 21 or later. Android Studio's bundled one is found
automatically. The first one that exists and is 21 or later is used:

1. `--java-home` or `"java_home"` in `swiftshot.json`
2. `SWIFTSHOT_JAVA_HOME`
3. `JAVA_HOME`
4. Android Studio's JDK: `/Applications/Android Studio.app`, `~/Applications/Android Studio.app`,
   `/opt/android-studio/jbr`
5. `java` on `PATH`

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
swiftshot --version    # swiftshot 0.4.0, or "swiftshot 0.4.0 (android)" in a Gradle project
swiftshot devices      # iOS: installed runtimes and devices; in a Gradle project: Android devices
```

## Update

Homebrew: `brew upgrade swiftshot`, uninstall with `brew uninstall swiftshot`.

Install script: run it again. To uninstall, delete `~/.swiftshot`.

Caches can be deleted at any time: `~/Library/Caches/swiftshot` on a Mac,
`~/.cache/swiftshot` on Linux.
