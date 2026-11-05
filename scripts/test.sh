#!/usr/bin/env bash
# Regenerate the Xcode project and run the unit tests.
# Full log goes to build.noindex/test.log; a short summary is printed.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build.noindex
xcodegen generate --quiet
xcodebuild test -project SideB.xcodeproj -scheme SideB \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build.noindex "$@" > build.noindex/test.log 2>&1
status=$?
grep -E "error:|failed \(|Executed [0-9]+ tests?,|\*\* TEST" build.noindex/test.log | grep -v -e "produced no further output" -e "Code=4097" | tail -4
exit $status
