## Requirements

- Apple silicon Mac
- Xcode 26.6 or 27.x
- The simulator runtimes you want to render (Xcode > Settings > Components)
- An app with `#Preview`s, iOS 17 or later. Nothing has to be added to the project.

## Install script

```
curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | sh
export PATH="$HOME/.swiftshot/bin:$PATH"
```

| variable | default | |
|---|---|---|
| `SWIFTSHOT_VERSION` | latest | release to install, e.g. `0.2.0` |
| `SWIFTSHOT_PREFIX` | `~/.swiftshot` | install location |

The script downloads `swiftshot-macos-arm64.tar.gz` from the
[releases page](https://github.com/LukasAnda/swiftshot/releases) and checks its SHA-256.

## From source

```
git clone https://github.com/LukasAnda/swiftshot
cd swiftshot
make install
```

## Check it

```
swiftshot --version
swiftshot devices      # installed runtimes and devices
```

## Update

Run the install script again. To uninstall, delete `~/.swiftshot`.
