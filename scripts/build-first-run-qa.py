#!/usr/bin/env python3
"""Build isolated Mac/iOS first-run apps without resetting installed apps.

Only identity/storage names and the LAN listen port change in the staged copy.
Permission requests, checks, restart and service startup use production sources.
This is local onboarding QA, not a Gatekeeper/notarization distribution test.
"""
import argparse
import json
import os
import plistlib
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid


def replace(path, old, new, count=1):
    text = path.read_text()
    if text.count(old) != count:
        raise RuntimeError(f"Source changed; inspect isolation patch: {path.name}")
    path.write_text(text.replace(old, new))


def run(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true', help='Stage sources without building or signing')
    parser.add_argument('--output', type=Path, help='New output directory (never overwritten)')
    parser.add_argument('--platform', choices=['macos', 'ios', 'both'], default='macos')
    parser.add_argument('--team', help='Apple Developer Team for the isolated iOS development identity')
    args = parser.parse_args()
    if args.platform in ['ios', 'both'] and not args.prepare_only and not args.team:
        parser.error('--team is required for an iOS device build')
    root = Path(__file__).resolve().parent.parent
    token = uuid.uuid4().hex[:12]
    bundle_id = f'dev.chordesk.firstrun.q{token}'
    ios_bundle_id = bundle_id + '.ios'
    destination = (args.output or Path(tempfile.gettempdir()) / 'ChordeskFirstRun' / token).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    stage = destination / 'source'
    stage.mkdir()
    for name in ['iPhoneDuoDemo', 'Tests', 'Native/Tailnet']:
        shutil.copytree(root / name, stage / name)
    shutil.copy2(root / 'Package.swift', stage / 'Package.swift')
    (stage / 'scripts').mkdir()
    shutil.copy2(root / 'scripts/build-workbench.sh', stage / 'scripts/build-workbench.sh')
    version_match = re.search(r'<key>CFBundleShortVersionString</key><string>([^<]+)</string>',
                              (stage / 'scripts/build-workbench.sh').read_text())
    if not version_match:
        raise RuntimeError('Cannot identify Mac QA version')
    mac_version = version_match.group(1)
    mac_name = f'Chordesk First Run {mac_version}'
    mac_title = f'Chordesk · 首次安装测试 {mac_version}'
    (stage / 'Branding').mkdir()
    shutil.copy2(root / 'Branding/Chordesk.icns', stage / 'Branding/Chordesk.icns')
    if args.platform in ['ios', 'both']:
        shutil.copytree(root / 'iPhoneDuoDemo.xcodeproj', stage / 'iPhoneDuoDemo.xcodeproj',
                        ignore=shutil.ignore_patterns('xcuserdata', '*.xcuserstate'))
        project = stage / 'iPhoneDuoDemo.xcodeproj/project.pbxproj'
        replace(project, 'PRODUCT_BUNDLE_IDENTIFIER = dev.iphoneduo.remotedemo;',
                f'PRODUCT_BUNDLE_IDENTIFIER = {ios_bundle_id};', count=4)
        replace(project, 'PRODUCT_BUNDLE_IDENTIFIER = dev.iphoneduo.remotedemo.uitests;',
                f'PRODUCT_BUNDLE_IDENTIFIER = {ios_bundle_id}.uitests;', count=2)
        replace(stage / 'iPhoneDuoDemo/Info.plist', '<string>Chordesk</string>',
                '<string>Chordesk First Run</string>')

    # A different bundle ID isolates UserDefaults and real macOS permissions.
    # Explicit namespaces also isolate stores that do not follow the bundle ID.
    replace(stage / 'iPhoneDuoDemo/LANWire.swift',
            '"dev.iphoneduo.remote-pairing"', f'"{bundle_id}.pairing"')
    replace(stage / 'Native/Tailnet/keychain.c',
            'CFSTR("dev.chordesk.embedded-tailnet")', f'CFSTR("{bundle_id}.tailnet")')
    replace(stage / 'iPhoneDuoDemo/EmbeddedTailnet.swift',
            '"Chordesk/Tailnet"', f'"Chordesk/FirstRunQA/{token}/Tailnet"')
    replace(stage / 'iPhoneDuoDemo/EmbeddedTailnet.swift',
            'let name = "chordesk-mac"', f'let name = "chordesk-qa-{token}"')
    replace(stage / 'iPhoneDuoDemo/EmbeddedTailnet.swift',
            'let name = "chordesk-iphone"', f'let name = "chordesk-qa-iphone-{token}"')
    # The real host may keep its LAN service online on 49173.
    replace(stage / 'iPhoneDuoDemo/LANHost.swift',
            'LANTransport.listener(secret: pairingSecret, localAddress: localBind)',
            'LANTransport.listener(secret: pairingSecret, localAddress: localBind, port: .any)')
    replace(stage / 'iPhoneDuoDemo/LANHost.swift',
            'LANStatus(name: Host.current().localizedName ?? "Mac",',
            'LANStatus(name: (Host.current().localizedName ?? "Mac") + " · 首次安装测试",')
    replace(stage / 'iPhoneDuoDemo/LANHostView.swift',
            'Text("Chordesk").font(.largeTitle.weight(.semibold))',
            f'Text("{mac_title}").font(.largeTitle.weight(.semibold))')
    replace(stage / 'iPhoneDuoDemo/WorkbenchApp.swift',
            'Window("Chordesk · Mac 主机",', f'Window("{mac_title}",')
    replace(stage / 'iPhoneDuoDemo/WorkbenchApp.swift',
            'MenuBarExtra("Chordesk",', f'MenuBarExtra("{mac_name}",')
    build_script = stage / 'scripts/build-workbench.sh'
    replace(build_script, 'dev.iphoneduo.workbench', bundle_id, count=2)
    replace(build_script, '<key>CFBundleName</key><string>Chordesk</string>',
            f'<key>CFBundleName</key><string>{mac_name}</string>')
    replace(build_script, '<key>CFBundleDisplayName</key><string>Chordesk</string>',
            f'<key>CFBundleDisplayName</key><string>{mac_name}</string>')
    # Never run the QA app from Documents/Desktop/Downloads, even if the
    # caller stores staged sources there. Those locations have folder TCC.
    runtime = Path(tempfile.gettempdir()) / f'ChordeskFirstRunRuntime-{token}'
    app = runtime / f'{mac_name}.app'
    # File providers can attach FinderInfo to app bundles in Documents during
    # a build. Keep device products outside synced source folders for signing.
    ios_build = Path(tempfile.gettempdir()) / f'ChordeskFirstRunIOS-{token}'
    ios_app = ios_build / 'Build/Products/Debug-iphoneos/iPhoneDuoDemo.app'
    manifest = dict(bundleID=bundle_id, app=str(app), pairingService=f'{bundle_id}.pairing',
                    tailnetService=f'{bundle_id}.tailnet',
                    tailnetDirectory=f'Chordesk/FirstRunQA/{token}/Tailnet',
                    platform=args.platform, iosBundleID=ios_bundle_id, iosApp=str(ios_app),
                    iosDerivedData=str(ios_build),
                    sourceCommit=output('git', '-C', str(root), 'rev-parse', 'HEAD'),
                    sourceDirty=bool(output('git', '-C', str(root), 'status', '--porcelain')),
                    purpose='Local first-run QA; no production state reset; no upload')
    (destination / 'isolation.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if args.prepare_only:
        print(destination)
        return
    if output('uname', '-m') != 'arm64':
        raise RuntimeError('This QA build requires Apple Silicon.')
    go = os.environ.get('CHORDESK_GO') or shutil.which('go')
    if not go:
        raise RuntimeError('Set CHORDESK_GO to the installed Go 1.27.1+ executable.')
    targets = ['macos', 'ios'] if args.platform == 'both' else [args.platform]
    framework_args = []
    for target in targets:
        sdk_name, goos, triple = ('macosx', 'darwin', 'arm64-apple-macos15.2') if target == 'macos' else ('iphoneos', 'ios', 'arm64-apple-ios17.0')
        sdk = output('xcrun', '--sdk', sdk_name, '--show-sdk-path')
        clang = output('xcrun', '--sdk', sdk_name, '--find', 'clang')
        library = stage / f'build/tailnet/{target}/libChordeskTailnet.a'
        library.parent.mkdir(parents=True)
        env = dict(os.environ, CGO_ENABLED='1', GOOS=goos, GOARCH='arm64', CC=clang,
                   CGO_CFLAGS=f'-target {triple} -isysroot {sdk}',
                   CGO_LDFLAGS=f'-target {triple} -isysroot {sdk}')
        run(go, 'build', '-mod=readonly', '-trimpath', '-ldflags=-w -s', '-buildmode=c-archive',
            '-o', str(library), cwd=stage / 'Native/Tailnet', env=env)
        framework_args += ['-library', str(library), '-headers', str(stage / 'Native/Tailnet/include')]
    run('xcodebuild', '-create-xcframework', *framework_args,
        '-output', str(stage / 'build/tailnet/ChordeskTailnet.xcframework'))
    if 'macos' in targets:
        env = dict(os.environ, DUO_BUILD_PATH=str(runtime / 'swift-build'), DUO_APP_BUNDLE=str(app))
        run('/bin/zsh', str(build_script), cwd=stage, env=env)
        run('codesign', '--verify', '--deep', '--strict', str(app))
        actual = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleIdentifier']
        if actual != bundle_id:
            raise RuntimeError('Refusing to use a QA app with an unexpected identity.')
        print(f'Mac QA app ready (not launched): {app}')
    if 'ios' in targets:
        run('xcodebuild', '-project', str(stage / 'iPhoneDuoDemo.xcodeproj'), '-scheme', 'iPhoneDuoDemo',
            '-configuration', 'Debug', '-destination', 'generic/platform=iOS',
            '-derivedDataPath', str(ios_build), f'DEVELOPMENT_TEAM={args.team}',
            '-allowProvisioningUpdates', 'build', cwd=stage)
        run('codesign', '--verify', '--deep', '--strict', str(ios_app))
        actual = plistlib.loads((ios_app / 'Info.plist').read_bytes())['CFBundleIdentifier']
        if actual != ios_bundle_id:
            raise RuntimeError('Refusing to use an iOS QA app with an unexpected identity.')
        print(f'iOS QA app ready (not installed or launched): {ios_app}')
    print(f'Isolation manifest: {destination / "isolation.json"}')


if __name__ == '__main__':
    main()
