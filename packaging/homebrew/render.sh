#!/bin/sh
# Writes the Homebrew formula for a release: render.sh <version> <download url> <macOS sha256> <Linux sha256>
set -eu
sed -e "s|@VERSION@|$1|; s|@URL@|$2|g; s|@MACOS_SHA256@|$3|; s|@LINUX_SHA256@|$4|" "$(dirname "$0")/swiftshot.rb"
