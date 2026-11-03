#!/usr/bin/env python3
"""Build-time only: deterministic Finder layout, without automating Finder.

Requires ds-store==1.3.1 and mac-alias==2.2.2 (both MIT); neither is bundled.
The generated image contains the App, Applications link and hidden appearance files.
"""
import argparse
import pathlib
import subprocess
import tempfile

try:
    from ds_store import DSStore
    from mac_alias import Alias
except ImportError:
    raise SystemExit("DMG layout requires ds-store==1.3.1 in the build Python. See docs/developer/DEVELOPMENT.md.")


def run(*args):
    subprocess.run([str(x) for x in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--volume", default="Chordesk")
    args = parser.parse_args()
    stage, output = args.stage.resolve(), args.output.absolute()
    if output.exists() or not (stage / "Chordesk.app").is_dir():
        raise SystemExit("A new output path and a staged Chordesk.app are required.")
    visible = {p.name for p in stage.iterdir() if not p.name.startswith(".")}
    if visible != {"Chordesk.app", "Applications"} or not (stage / "Applications").is_symlink():
        raise SystemExit("Expected only Chordesk.app and an Applications link in the installer.")
    background = stage / ".background"
    background.mkdir(exist_ok=True)
    run("xcrun", "swift", pathlib.Path(__file__).with_name("dmg-background.swift"), background / "install.png")
    run("xcrun", "swift", pathlib.Path(__file__).with_name("dmg-background.swift"), background / "install@2x.png", "2")
    run("tiffutil", "-cathidpicheck", background / "install.png", background / "install@2x.png", "-out", background / "install.tiff")
    (background / "install.png").unlink()
    (background / "install@2x.png").unlink()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ChordeskDMG-", dir="/private/tmp") as temporary:
        temporary = pathlib.Path(temporary)
        image, mount = temporary / "installer.dmg", temporary / "mount"
        mount.mkdir()
        run("hdiutil", "create", "-volname", args.volume, "-fs", "HFS+", "-srcfolder", stage, "-format", "UDRW", image)
        run("hdiutil", "attach", "-nobrowse", "-noautoopen", "-mountpoint", mount, image)
        try:
            with DSStore.open(str(mount / ".DS_Store"), "w+") as store:
                store["."]["bwsp"] = {"ShowToolbar": False, "ShowStatusBar": False,
                    "ShowPathbar": False, "ShowSidebar": False, "ShowTabView": False,
                    "WindowBounds": "{{100, 100}, {720, 420}}"}
                # Finder ignores the entire icon-view dictionary if required
                # color/scroll defaults are omitted, even with a picture backdrop.
                store["."]["icvp"] = {"viewOptionsVersion": 1, "backgroundType": 2,
                    "backgroundImageAlias": Alias.for_file(str(mount / ".background/install.tiff")).to_bytes(),
                    "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
                    "iconSize": 104.0, "textSize": 14.0, "arrangeBy": "none",
                    "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
                    "scrollPositionX": 0.0, "scrollPositionY": 0.0,
                    "labelOnBottom": True, "showIconPreview": True, "showItemInfo": False}
                store["."]["vSrn"] = ("long", 1)
                store["."]["icvl"] = ("type", b"icnv")
                store["Chordesk.app"]["Iloc"] = (190, 180)
                store["Applications"]["Iloc"] = (530, 180)
        finally:
            run("hdiutil", "detach", mount)
        run("hdiutil", "convert", image, "-format", "UDZO", "-o", output)
    run("hdiutil", "verify", output)
    print("Prepared drag-to-install DMG:", output)


if __name__ == "__main__":
    main()
