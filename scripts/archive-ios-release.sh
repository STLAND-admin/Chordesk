#!/bin/zsh
# Archive only. Organizer validation/upload and beta release remain explicit steps.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' 'CHORDESK_DISTRIBUTION_TEAM=TEAM_ID ./scripts/archive-ios-release.sh'
    exit 0
fi
if [[ -z "${CHORDESK_DISTRIBUTION_TEAM:-}" ]]; then
    printf '%s\n' 'Set CHORDESK_DISTRIBUTION_TEAM only after paid Developer Program membership is active. A Personal Team development build is not TestFlight distribution.' >&2
    exit 1
fi
archive_path="${CHORDESK_ARCHIVE_PATH:-$PWD/release-artifacts/Chordesk.xcarchive}"
if [[ -e "$archive_path" ]]; then
    printf '%s\n' 'Archive exists. Choose a new CHORDESK_ARCHIVE_PATH; existing builds are not overwritten.' >&2
    exit 1
fi
xcodebuild -project iPhoneDuoDemo.xcodeproj -scheme iPhoneDuoDemo -configuration Release -destination 'generic/platform=iOS' -archivePath "$archive_path" DEVELOPMENT_TEAM="$CHORDESK_DISTRIBUTION_TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates archive
printf '%s\n' "Archived: $archive_path" 'In Xcode Organizer: Validate, Distribute to App Store Connect, then select the external Duo test group. This script does not upload or notify testers.'
