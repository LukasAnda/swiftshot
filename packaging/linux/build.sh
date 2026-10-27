#!/bin/sh
# Builds swiftshot_<version>_all.deb and swiftshot-<version>-1.noarch.rpm (+ .sha256) from the
# Linux archive: build.sh <swiftshot-android.tar.gz> <version> <out dir>. Uses nfpm (downloaded
# once, pinned, if it isn't on the PATH).
set -eu
archive=$1; version=$2; out=$3
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
tar -xzf "$archive" -C "$work"
nfpm=$(command -v nfpm || true)
if [ -z "$nfpm" ]; then
  n=2.41.1
  curl -fsSL "https://github.com/goreleaser/nfpm/releases/download/v$n/nfpm_${n}_$(uname -s)_$(uname -m).tar.gz" | tar -xz -C "$work" nfpm
  nfpm=$work/nfpm
fi
mkdir -p "$out"
sed -e "s|@ROOT@|$work/swiftshot|g; s|@VERSION@|$version|" "$here/nfpm.yaml" > "$work/nfpm.yaml"
for p in deb rpm; do "$nfpm" pkg --config "$work/nfpm.yaml" --packager $p --target "$out/" >/dev/null; done
cd "$out"
# Also under fixed names, for the releases/latest/download links in the docs.
cp swiftshot_${version}_all.deb swiftshot_all.deb
cp swiftshot-${version}-1.noarch.rpm swiftshot.noarch.rpm
for f in swiftshot_${version}_all.deb swiftshot-${version}-1.noarch.rpm swiftshot_all.deb swiftshot.noarch.rpm; do
  (shasum -a 256 "$f" 2>/dev/null || sha256sum "$f") > "$f.sha256"
  echo "$out/$f"
done
