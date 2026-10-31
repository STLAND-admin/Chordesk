#!/bin/zsh
# Builds the pinned userspace Tailscale engine; never starts a node or signs in.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
tailnet_go="${CHORDESK_GO:-$(command -v go || true)}"
[[ -n "$tailnet_go" ]] || { print -u2 'Install Go 1.27.1+ or set CHORDESK_GO to its binary.'; exit 1; }
tailnet_output="$root/build/tailnet"
mkdir -p "$tailnet_output"
for target in macos ios simulator simulator-intel; do
    mkdir -p "$tailnet_output/$target"
    case "$target" in
        macos) sdk=macosx; goos=darwin; goarch=arm64; triple=arm64-apple-macos15.2 ;;
        ios) sdk=iphoneos; goos=ios; goarch=arm64; triple=arm64-apple-ios17.0 ;;
        simulator) sdk=iphonesimulator; goos=ios; goarch=arm64; triple=arm64-apple-ios17.0-simulator ;;
        simulator-intel) sdk=iphonesimulator; goos=ios; goarch=amd64; triple=x86_64-apple-ios17.0-simulator ;;
    esac
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
    clang="$(xcrun --sdk "$sdk" --find clang)"
    print "Building embedded tailnet: $target"
    (cd Native/Tailnet
     CGO_ENABLED=1 GOOS="$goos" GOARCH="$goarch" CC="$clang" \
     CGO_CFLAGS="-target $triple -isysroot $sdk_path" \
     CGO_LDFLAGS="-target $triple -isysroot $sdk_path" \
     "$tailnet_go" build -mod=readonly -trimpath -ldflags='-w -s' -buildmode=c-archive \
     -o "$tailnet_output/$target/libChordeskTailnet.a")
done
mkdir -p "$tailnet_output/simulator-universal"
lipo -create "$tailnet_output/simulator/libChordeskTailnet.a" "$tailnet_output/simulator-intel/libChordeskTailnet.a" \
    -output "$tailnet_output/simulator-universal/libChordeskTailnet.a"
# Only replace this generated artifact, not a source or installed app.
if [[ -d "$tailnet_output/ChordeskTailnet.xcframework" ]]; then
    mv "$tailnet_output/ChordeskTailnet.xcframework" "$tailnet_output/previous-$(date +%s).xcframework"
fi
xcodebuild -create-xcframework \
    -library "$tailnet_output/macos/libChordeskTailnet.a" -headers "$root/Native/Tailnet/include" \
    -library "$tailnet_output/ios/libChordeskTailnet.a" -headers "$root/Native/Tailnet/include" \
    -library "$tailnet_output/simulator-universal/libChordeskTailnet.a" -headers "$root/Native/Tailnet/include" \
    -output "$tailnet_output/ChordeskTailnet.xcframework"
