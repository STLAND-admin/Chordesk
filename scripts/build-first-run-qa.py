#!/usr/bin/env python3
"""Build an isolated Mac first-run app without resetting the installed app.

Only identity/storage names and the LAN listen port change in the staged copy.
Permission requests, checks, restart and service startup use production sources.
This is local onboarding QA, not a Gatekeeper/notarization distribution test.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
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
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    token = uuid.uuid4().hex[:12]
    bundle_id = f'dev.chordesk.firstrun.q{token}'
    destination = (args.output or root / 'build' / 'first-run' / token).resolve()
    destination.mkdir(parents=True, exist_ok=False)
    stage = destination / 'source'
    stage.mkdir()
    for name in ['iPhoneDuoDemo', 'Tests', 'Native/Tailnet']:
        shutil.copytree(root / name, stage / name)
    shutil.copy2(root / 'Package.swift', stage / 'Package.swift')
    (stage / 'scripts').mkdir()
    shutil.copy2(root / 'scripts/build-workbench.sh', stage / 'scripts/build-workbench.sh')
    (stage / 'Branding').mkdir()
    shutil.copy2(root / 'Branding/Chordesk.icns', stage / 'Branding/Chordesk.icns')

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
    # The real host may keep its LAN service online on 49173.
    replace(stage / 'iPhoneDuoDemo/LANHost.swift',
            'LANTransport.listener(secret: pairingSecret, localAddress: localBind)',
            'LANTransport.listener(secret: pairingSecret, localAddress: localBind, port: .any)')
    replace(stage / 'iPhoneDuoDemo/LANHost.swift',
            'LANStatus(name: Host.current().localizedName ?? "Mac",',
            'LANStatus(name: (Host.current().localizedName ?? "Mac") + " · 首次安装测试",')
    replace(stage / 'iPhoneDuoDemo/LANHostView.swift',
            'Text("Chordesk").font(.largeTitle.weight(.semibold))',
            'Text("Chordesk · 首次安装测试").font(.largeTitle.weight(.semibold))')
    replace(stage / 'iPhoneDuoDemo/WorkbenchApp.swift',
            'Window("Chordesk · Mac 主机",', 'Window("Chordesk · 首次安装测试",')
    replace(stage / 'iPhoneDuoDemo/WorkbenchApp.swift',
            'MenuBarExtra("Chordesk",', 'MenuBarExtra("Chordesk 首次安装测试",')
    build_script = stage / 'scripts/build-workbench.sh'
    replace(build_script, 'dev.iphoneduo.workbench', bundle_id, count=2)
    replace(build_script, '<key>CFBundleName</key><string>Chordesk</string>',
            '<key>CFBundleName</key><string>Chordesk First Run</string>')
    replace(build_script, '<key>CFBundleDisplayName</key><string>Chordesk</string>',
            '<key>CFBundleDisplayName</key><string>Chordesk First Run</string>')
    app = destination / 'Chordesk First Run.app'
    manifest = dict(bundleID=bundle_id, app=str(app), pairingService=f'{bundle_id}.pairing',
                    tailnetService=f'{bundle_id}.tailnet',
                    tailnetDirectory=f'Chordesk/FirstRunQA/{token}/Tailnet',
                    sourceCommit=output('git', '-C', str(root), 'rev-parse', 'HEAD'),
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
    sdk = output('xcrun', '--sdk', 'macosx', '--show-sdk-path')
    clang = output('xcrun', '--sdk', 'macosx', '--find', 'clang')
    library = stage / 'build/tailnet/macos/libChordeskTailnet.a'
    library.parent.mkdir(parents=True)
    env = dict(os.environ, CGO_ENABLED='1', GOOS='darwin', GOARCH='arm64', CC=clang,
               CGO_CFLAGS=f'-target arm64-apple-macos15.2 -isysroot {sdk}',
               CGO_LDFLAGS=f'-target arm64-apple-macos15.2 -isysroot {sdk}')
    run(go, 'build', '-mod=readonly', '-trimpath', '-ldflags=-w -s', '-buildmode=c-archive',
        '-o', str(library), cwd=stage / 'Native/Tailnet', env=env)
    run('xcodebuild', '-create-xcframework', '-library', str(library),
        '-headers', str(stage / 'Native/Tailnet/include'),
        '-output', str(stage / 'build/tailnet/ChordeskTailnet.xcframework'))
    env = dict(os.environ, DUO_BUILD_PATH=str(destination / 'swift-build'), DUO_APP_BUNDLE=str(app))
    run('/bin/zsh', str(build_script), cwd=stage, env=env)
    run('codesign', '--verify', '--deep', '--strict', str(app))
    actual = output('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', str(app / 'Contents/Info.plist'))
    if actual != bundle_id:
        raise RuntimeError('Refusing to use a QA app with an unexpected identity.')
    print(f'QA app ready (not launched): {app}')
    print(f'Isolation manifest: {destination / "isolation.json"}')


if __name__ == '__main__':
    main()
