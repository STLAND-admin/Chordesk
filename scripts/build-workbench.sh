#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d build/tailnet/ChordeskTailnet.xcframework ]]; then ./scripts/build-tailnet.sh; fi
duo_scratch_path="${DUO_BUILD_PATH:-/private/tmp/DuoWorkbenchBuild}"
duo_configuration="${DUO_BUILD_CONFIGURATION:-debug}"
case "$duo_configuration" in debug|release) ;; *) printf '%s\n' 'Configuration must be debug or release.' >&2; exit 1;; esac
duo_compile_args=()
# Distributed artifacts must not embed this Mac's username or checkout path.
if [[ "$duo_configuration" == release ]]; then
    duo_compile_args=(-Xswiftc -file-prefix-map -Xswiftc "$PWD=/Chordesk")
fi
swift build --configuration "$duo_configuration" --scratch-path "$duo_scratch_path" "${duo_compile_args[@]}"
duo_binary_path=$(swift build --configuration "$duo_configuration" --scratch-path "$duo_scratch_path" --show-bin-path)
app_bundle="${DUO_APP_BUNDLE:-$duo_scratch_path/Chordesk.app}"
if [[ "${1:-}" == "--install" ]]; then
    app_bundle="$HOME/Applications/Chordesk.app"
    legacy_bundle="$HOME/Applications/DuoWorkbench.app"
    # Dock resolves symbolic launch links to the actual .app filename. Always
    # install a real Chordesk.app; do not silently create a second legacy host.
    if [[ -d "$legacy_bundle" && ! -L "$legacy_bundle" ]]; then
        printf '%s\n' 'Quit the legacy host and migrate its signed bundle to Chordesk.app first; see docs/DEVELOPMENT.md.' >&2
        exit 1
    fi
    if [[ -L "$app_bundle" ]]; then
        printf '%s\n' 'Chordesk.app must be the actual application bundle, not a launch link.' >&2
        exit 1
    fi
elif [[ $# -gt 0 ]]; then
    printf '%s\n' 'Usage: build-workbench.sh [--install]' >&2
    exit 1
fi
if [[ -e "$app_bundle/Contents/Info.plist" ]]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")
    if [[ "$existing_id" != "dev.iphoneduo.workbench" ]]; then
        printf '%s\n' 'Refusing to replace a different application.' >&2
        exit 1
    fi
fi
# Build a fresh bundle: merging into an older branded app leaves obsolete sealed
# resources behind and invalidates its signature. Keep the prior app recoverable.
bundle_staging=$(mktemp -d /private/tmp/ChordeskPackage.XXXXXX)
prepared_bundle="$bundle_staging/Chordesk.app"
app_dir="$prepared_bundle/Contents"
mkdir -p "$app_dir/MacOS" "$app_dir/Resources"
# Bundle.module resolves from the application Resources directory.
ditto "$duo_binary_path/DuoWorkbench_DuoWorkbench.bundle" "$app_dir/Resources/DuoWorkbench_DuoWorkbench.bundle"
cp -X Branding/Chordesk.icns "$app_dir/Resources/Chordesk.icns"
cp -X "$duo_binary_path/DuoWorkbench" "$app_dir/MacOS/DuoWorkbench"
cat > "$app_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DuoWorkbench</string>
<key>CFBundleIdentifier</key><string>dev.iphoneduo.workbench</string>
<key>CFBundleName</key><string>Chordesk</string>
<key>CFBundleDisplayName</key><string>Chordesk</string>
<key>CFBundleIconFile</key><string>Chordesk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.19.0</string>
<key>CFBundleVersion</key><string>27</string>
<key>LSMinimumSystemVersion</key><string>15.2</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppleEventsUsageDescription</key><string>通过系统自带的 System Events 执行左右切换 Mac 桌面的快捷键。仅从本机设置请求授权。</string>
<key>NSLocalNetworkUsageDescription</key><string>让你配对的 iPhone 在局域网中查看并控制所选 Mac 显示器。</string>
</dict></plist>
PLIST
xattr -cr "$prepared_bundle"
codesign --force --sign "${DUO_SIGNING_IDENTITY:-Apple Development}" "$prepared_bundle"
codesign --verify --strict "$prepared_bundle"
mkdir -p "$(dirname "$app_bundle")"
if [[ -e "$app_bundle" ]]; then mv "$app_bundle" "$bundle_staging/previous.app"; fi
if ! mv "$prepared_bundle" "$app_bundle"; then
    if [[ -e "$bundle_staging/previous.app" ]]; then mv "$bundle_staging/previous.app" "$app_bundle"; fi
    exit 1
fi
codesign --verify --strict "$app_bundle"
printf '%s\n' "Built: $app_bundle"
