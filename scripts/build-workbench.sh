#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
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
legacy_launch_link=""
if [[ "${1:-}" == "--install" ]]; then
    app_bundle="$HOME/Applications/Chordesk.app"
    legacy_bundle="$HOME/Applications/DuoWorkbench.app"
    # Existing development installs retain their signed path and TCC identity.
    # Expose the branded entry instead of leaving DuoWorkbench visible in Finder.
    if [[ -d "$legacy_bundle" && ! -L "$legacy_bundle" ]]; then
        if [[ -L "$app_bundle" ]]; then
            link_target=$(readlink "$app_bundle")
            if [[ "$link_target" != "DuoWorkbench.app" && "$link_target" != "$legacy_bundle" ]]; then
                printf '%s\n' 'Refusing to replace an unrelated Chordesk launch link.' >&2
                exit 1
            fi
        elif [[ -e "$app_bundle" ]]; then
            printf '%s\n' 'Both Chordesk and a legacy install exist; choose one before installing.' >&2
            exit 1
        fi
        legacy_launch_link="$app_bundle"
        app_bundle="$legacy_bundle"
    elif [[ -L "$app_bundle" ]]; then
        printf '%s\n' 'Refusing to replace an unresolved Chordesk launch link.' >&2
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
<key>CFBundleShortVersionString</key><string>0.18.1</string>
<key>CFBundleVersion</key><string>26</string>
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
if [[ -n "$legacy_launch_link" ]]; then
    if [[ ! -L "$legacy_launch_link" ]]; then
        ln -s "DuoWorkbench.app" "$legacy_launch_link"
    fi
    # Finder hides only the legacy entry; its contents and signature stay intact.
    chflags hidden "$app_bundle"
    printf '%s\n' "Launch: $legacy_launch_link"
fi
printf '%s\n' "Built: $app_bundle"
