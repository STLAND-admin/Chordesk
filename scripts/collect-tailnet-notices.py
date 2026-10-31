#!/usr/bin/env python3
"""Collect license texts from the pinned modules linked on Apple platforms.

Run with the same CHORDESK_GO/GOMODCACHE as build-tailnet.sh after downloading
modules. The generated notice contains versions and license texts, never paths
to a developer's checkout or cache. Review changes before distribution.
"""
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GO = os.environ.get("CHORDESK_GO", "go")
MODULE = ROOT / "Native/Tailnet"
modules = {}

for target, sdk, triple in [("darwin", "macosx", "arm64-apple-macos15.2"), ("ios", "iphoneos", "arm64-apple-ios17.0")]:
    sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
    cc = subprocess.check_output(["xcrun", "--sdk", sdk, "--find", "clang"], text=True).strip()
    env = dict(os.environ, GOOS=target, GOARCH="arm64", CGO_ENABLED="1", CC=cc,
               CGO_CFLAGS=f"-target {triple} -isysroot {sdk_path}")
    stream = subprocess.check_output([GO, "list", "-mod=readonly", "-deps", "-json", "."], cwd=MODULE, env=env, text=True)
    decoder = json.JSONDecoder()
    while stream.strip():
        item, end = decoder.raw_decode(stream.lstrip())
        stream = stream.lstrip()[end:]
        mod = item.get("Module")
        if mod and not mod.get("Main"):
            modules[mod["Path"]] = mod

def license_file(path):
    name = path.name.upper()
    return path.is_file() and (name in ("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT", "PATENTS") or
        (name.startswith(("LICENSE.", "LICENCE.", "COPYING.", "NOTICE.")) and path.suffix.lower() not in (".go", ".js", ".py")))

parts = ["Chordesk — embedded networking third-party notices\n\n"
         "These components retain their original licenses. Chordesk's project license does not relicense them.\n"
         "Generated from the pinned dependency graph for macOS and iOS; includes nested upstream notices.\n"]
goroot = Path(subprocess.check_output([GO, "env", "GOROOT"], text=True).strip())
go_version = subprocess.check_output([GO, "env", "GOVERSION"], text=True).strip()
components = [("Go runtime and standard library", go_version, goroot, [goroot / "LICENSE"] + sorted(p for p in (goroot / "src/vendor").rglob("*") if license_file(p)))]
for name, mod in sorted(modules.items()):
    base = Path(mod["Dir"])
    files = sorted(p for p in base.rglob("*") if license_file(p))
    if not files:
        raise RuntimeError("Missing license for " + name)
    components.append((name, mod["Version"], base, files))
for name, version, base, files in components:
    parts.append(f"\n{'=' * 72}\n{name} {version}\n")
    for path in files:
        parts.append(f"\n--- {path.relative_to(base)} ---\n{path.read_text()}\n")
out = ROOT / "iPhoneDuoDemo/Resources/Legal/ThirdPartyNotices.txt"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text("".join(parts).rstrip() + "\n")
print(f"Collected {len(components)} components in {out.relative_to(ROOT)}")
