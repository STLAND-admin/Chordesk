#!/bin/zsh
# Export locally; never upload a build or submit a review.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' 'CHORDESK_DISTRIBUTION_TEAM=TEAM_ID CHORDESK_ARCHIVE_PATH=/path/Chordesk.xcarchive CHORDESK_EXPORT_PATH=/path/export ./scripts/export-ios-release.sh' 'Set CHORDESK_ALLOW_PROVISIONING_UPDATES=1 only when account-side certificate/profile changes are authorized.'
    exit 0
fi
: "${CHORDESK_DISTRIBUTION_TEAM:?Set the enrolled distribution Team ID}"
: "${CHORDESK_ARCHIVE_PATH:?Set the existing release archive path}"
: "${CHORDESK_EXPORT_PATH:?Set a new local export directory}"
[[ -d "$CHORDESK_ARCHIVE_PATH" ]] || { print -u2 'Archive not found'; exit 1; }
[[ ! -e "$CHORDESK_EXPORT_PATH" ]] || { print -u2 'Export directory already exists; choose another path'; exit 1; }
options_path="$(mktemp -t chordesk-export-options)"
trap 'rm -f "$options_path"' EXIT
python3 - "$options_path" "$CHORDESK_DISTRIBUTION_TEAM" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({'method': 'app-store-connect', 'destination': 'export',
                  'teamID': sys.argv[2], 'signingStyle': 'automatic',
                  'manageAppVersionAndBuildNumber': False,
                  'stripSwiftSymbols': True, 'uploadSymbols': True}, output)
PY
provisioning_args=()
if [[ "${CHORDESK_ALLOW_PROVISIONING_UPDATES:-0}" == 1 ]]; then
    provisioning_args=(-allowProvisioningUpdates)
fi
xcodebuild -exportArchive -archivePath "$CHORDESK_ARCHIVE_PATH" \
    -exportPath "$CHORDESK_EXPORT_PATH" -exportOptionsPlist "$options_path" \
    "${provisioning_args[@]}"
print "Exported locally: $CHORDESK_EXPORT_PATH"
print 'This App Store IPA is for App Store Connect distribution, not direct installation by sharing the file.'
