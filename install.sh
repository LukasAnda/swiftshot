#!/bin/sh
# Installs swiftshot from a GitHub release: the full tool on an Apple silicon Mac, the Android
# (Jetpack Compose) renderer on Linux or an Intel Mac (needs a JDK 21+).
#   curl -fsSL https://raw.githubusercontent.com/LukasAnda/swiftshot/main/install.sh | sh
#   SWIFTSHOT_VERSION=0.1.0 SWIFTSHOT_PREFIX=$HOME/.swiftshot sh install.sh
set -eu
version=${SWIFTSHOT_VERSION:-latest}
prefix=${SWIFTSHOT_PREFIX:-$HOME/.swiftshot}
repo=https://github.com/LukasAnda/swiftshot
if [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ -z "${SWIFTSHOT_ANDROID_ONLY:-}" ]; then file=swiftshot-macos-arm64.tar.gz
else file=swiftshot-android.tar.gz; fi
if [ "$version" = latest ]; then url=$repo/releases/latest/download/$file
else url=$repo/releases/download/v$version/$file; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $url"
curl -fsSL "$url" -o "$tmp/swiftshot.tar.gz"
curl -fsSL "$url.sha256" -o "$tmp/swiftshot.tar.gz.sha256"
(cd "$tmp" && expected=$(cut -d' ' -f1 swiftshot.tar.gz.sha256) && actual=$( (command -v shasum >/dev/null && shasum -a 256 swiftshot.tar.gz || sha256sum swiftshot.tar.gz) | cut -d' ' -f1) && [ "$expected" = "$actual" ]) \
  || { echo "checksum mismatch" >&2; exit 1; }
mkdir -p "$prefix"
tar -xzf "$tmp/swiftshot.tar.gz" -C "$tmp"
rm -rf "$prefix/bin" && cp -R "$tmp/swiftshot/bin" "$prefix/bin"
echo "Installed $("$prefix/bin/swiftshot" --version) to $prefix/bin"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "Add it to your PATH: export PATH=\"$prefix/bin:\$PATH\"" ;; esac
