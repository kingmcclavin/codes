#!/usr/bin/env bash
# Compiles StudyOS's Foundation-only code (Models, Persistence, Logic) together
# with Tests/LogicTests and runs the checks. Developer tool only — the app itself
# is built in Swift Playgrounds. Requires a Swift toolchain (Linux or macOS).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../StudyOS.swiftpm"
out="${TMPDIR:-/tmp}/studyos-logic-tests"
SWIFTC="${SWIFTC:-swiftc}"
"$SWIFTC" -swift-version 5 \
  "$app"/Models/*.swift "$app"/Persistence/*.swift "$app"/Logic/*.swift \
  "$here"/LogicTests/main.swift -o "$out"
"$out"
