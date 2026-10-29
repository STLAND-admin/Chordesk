#!/bin/zsh
# Run only after Developer Program activation and Developer ID setup.
# Produces a notarized DMG; never installs, launches, or uploads to GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' 'DEVELOPER_ID_APPLICATION="Developer ID Application: …" NOTARY_PROFILE="Chordesk-notary" ./scripts/package-macos-release.sh'
    exit 0
fi
release_identity="${DEVELOPER_ID_APPLICATION:-}"
case "$release_identity" in
    'Developer ID Application: '*) ;;
    *) printf '%s\n' 'Set DEVELOPER_ID_APPLICATION to your installed Developer ID Application identity; Apple Development is not accepted.' >&2; exit 1 ;;
esac
if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    printf '%s\n' 'Set NOTARY_PROFILE to an existing notarytool Keychain profile. Do not put credentials in this script.' >&2
    exit 1
fi
release_stage=$(mktemp -d /private/tmp/ChordeskRelease.XXXXXX)
release_app="$release_stage/Chordesk.app"
DUO_BUILD_CONFIGURATION=release DUO_BUILD_PATH="$release_stage/build" DUO_APP_BUNDLE="$release_app" DUO_SIGNING_IDENTITY="$release_identity" ./scripts/build-workbench.sh
codesign --force --options runtime --timestamp --sign "$release_identity" "$release_app"
codesign --verify --deep --strict "$release_app"
release_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release_app/Contents/Info.plist")
release_arch=$(uname -m)
release_output="${CHORDESK_RELEASE_OUTPUT:-$PWD/release-artifacts/mac-$release_version-$release_arch}"
if [[ -e "$release_output" ]]; then
    printf '%s\n' 'Output already exists; select a new CHORDESK_RELEASE_OUTPUT. Existing releases are not overwritten.' >&2
    exit 1
fi
ditto -c -k --keepParent "$release_app" "$release_stage/Chordesk.zip"
xcrun notarytool submit "$release_stage/Chordesk.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$release_app"
spctl --assess --type execute --verbose=2 "$release_app"
mkdir -p "$release_stage/image" "$release_output"
ditto "$release_app" "$release_stage/image/Chordesk.app"
ln -s /Applications "$release_stage/image/Applications"
cp docs/BETA-TESTING.md "$release_stage/image/READ-ME.md"
release_dmg="$release_output/Chordesk-$release_version-$release_arch.dmg"
hdiutil create -volname Chordesk -srcfolder "$release_stage/image" -format UDZO "$release_dmg"
codesign --timestamp --sign "$release_identity" "$release_dmg"
xcrun notarytool submit "$release_dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$release_dmg"
xcrun stapler validate "$release_dmg"
shasum -a 256 "$release_dmg" > "$release_output/SHA256SUMS.txt"
printf '%s\n' "Prepared: $release_dmg" 'Test on a clean Mac before attaching to a GitHub prerelease. No BlackHole or BetterDisplay is bundled.'
