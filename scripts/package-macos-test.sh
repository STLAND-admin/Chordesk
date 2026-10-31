#!/bin/zsh
# Explicit, unnotarized peer-testing export. Does not install or publish anything.
# The installed development app keeps its stable Apple Development signature.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' 'CHORDESK_TEST_OUTPUT=/absolute/new/folder ./scripts/package-macos-test.sh' \
      'Builds an Apple Silicon Release app with local ad hoc signing and an unnotarized DMG.' \
      'No developer membership, credentials, notarization, installation, or upload is used.'
    exit 0
fi
if [[ $# -gt 0 || "$(uname -m)" != arm64 ]]; then
    printf '%s\n' 'This peer-test package is currently prepared only on Apple Silicon, with no arguments.' >&2
    exit 1
fi
test_output="${CHORDESK_TEST_OUTPUT:-$PWD/release-artifacts/mac-test-0.20.0-build29-arm64}"
if [[ "$test_output" != /* || -e "$test_output" ]]; then
    printf '%s\n' 'Choose a new absolute CHORDESK_TEST_OUTPUT directory; existing artifacts are not overwritten.' >&2
    exit 1
fi
test_stage=$(mktemp -d /private/tmp/ChordeskPeerTest.XXXXXX)
test_app="$test_stage/image/Chordesk.app"
# '-' is intentional for this separately exported test artifact only.
DUO_BUILD_CONFIGURATION=release DUO_BUILD_PATH="$test_stage/build" \
  DUO_APP_BUNDLE="$test_app" DUO_SIGNING_IDENTITY=- ./scripts/build-workbench.sh
test_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$test_app/Contents/Info.plist")
test_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$test_app/Contents/Info.plist")
test_binary="$test_app/Contents/MacOS/DuoWorkbench"
if [[ "$(lipo -archs "$test_binary")" != arm64 ]]; then
    printf '%s\n' 'Unexpected architecture; artifact was not packaged.' >&2; exit 1
fi
if [[ -e "$test_app/Contents/embedded.provisionprofile" ]]; then
    printf '%s\n' 'A provisioning profile must not be included in this test export.' >&2; exit 1
fi
codesign --verify --deep --strict "$test_app"
cp docs/MAC-PEER-TEST.txt "$test_stage/image/先读我-安装与配对.txt"
ln -s /Applications "$test_stage/image/Applications"
test_name="Chordesk-Mac-$test_version-build$test_build-AppleSilicon-test.dmg"
hdiutil create -volname 'Chordesk Test' -srcfolder "$test_stage/image" -format UDZO "$test_stage/$test_name"
hdiutil verify "$test_stage/$test_name"
mkdir -p "$test_output"
mv "$test_stage/$test_name" "$test_output/"
cp docs/MAC-PEER-TEST.txt "$test_output/INSTALL-zh-CN.txt"
test_commit=$(git rev-parse HEAD)
{
    printf '%s\n' "Chordesk Mac $test_version / build $test_build" 'Architecture: arm64' \
      'Minimum OS: macOS 15.2 (older supported versions not hardware-tested)' \
      'Signing: local ad hoc; no verified publisher identity' 'Notarized: no' \
      "App source commit: $test_commit" \
      'Packaged from a fresh build; no user settings, pairing credentials, certificates or private keys included.'
} > "$test_output/BUILD-INFO.txt"
(cd "$test_output"; shasum -a 256 "$test_name" > SHA256SUMS.txt)
printf '%s\n' "Prepared: $test_output/$test_name" "Staging: $test_stage" \
  'Recipient must explicitly allow this unnotarized app in macOS Privacy & Security.' \
  'Test first launch and permissions on the recipient Mac. This script did not install or publish it.'
