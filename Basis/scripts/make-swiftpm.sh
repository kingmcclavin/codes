#!/bin/sh
# Assembles a Swift Playgrounds app package (Basis.swiftpm) from the app
# sources, so the app can be built and run directly on an iPad.
#
# Usage: scripts/make-swiftpm.sh [output-dir]   (default: build)
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-build}/Basis.swiftpm"
rm -rf "$OUT"
mkdir -p "$OUT"
cp Playgrounds/Package.swift "$OUT/"
for dir in App Calculator Canvas Engine Export Model Persistence Recognition Tools UI; do
    cp -R "Basis/$dir" "$OUT/$dir"
done
# App icon and accent color.
cp -R Basis/Resources/Assets.xcassets "$OUT/Assets.xcassets"
echo "Created $OUT"
