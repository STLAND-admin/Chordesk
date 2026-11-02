"""Exercise removal on temporary fixtures only; never call real TCC/Keychain.

Run with Python 3 on the build Mac. The distributed .command needs no Python.
"""
import json
import os
from pathlib import Path
import plistlib
import pty
import select
import subprocess
import tempfile
import time
import unittest


class MaintenanceToolTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ChordeskMaintenanceFixture-", dir="/private/tmp")
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.system_apps = self.root / "Applications"
        self.log = self.root / "calls.jsonl"
        self.bundle = "dev.iphoneduo.workbench"
        self.app = self.home / "Applications/Chordesk.app"
        self.other = self.system_apps / "Chordesk.app"  # Same filename, another identity.
        for app, identifier in [(self.app, self.bundle), (self.other, "dev.portalatlas.app")]:
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
        (self.home / ".Trash").mkdir()
        self.data = self.home / "Library/Application Support/Chordesk"
        self.data.mkdir(parents=True)
        (self.data / "fixture.txt").write_text("only this app")
        self.preferences = self.home / ("Library/Preferences/" + self.bundle + ".plist")
        self.preferences.parent.mkdir()
        self.preferences.write_bytes(plistlib.dumps({"fixture": "keep a recoverable backup"}))
        self.other_preferences = self.preferences.parent / "dev.portalatlas.app.plist"
        self.other_preferences.write_bytes(b"other product")
        self.running = False
        self.keychain_failure = False

    def tearDown(self):
        self.temporary.cleanup()

    def stage_script(self):
        source = Path(__file__).resolve().parents[1] / "Chordesk-Maintenance.command"
        text = source.read_text()
        prefix = 'for candidate in /Applications/Chordesk.app /Applications/DuoWorkbench.app'
        assert text.count(prefix) == 1
        text = text.replace(prefix, 'for candidate in "' + str(self.system_apps / "Chordesk.app") + '" "' + str(self.system_apps / "DuoWorkbench.app") + '"')
        text = text.replace('readonly chordesk_home="$HOME"', 'readonly chordesk_home="' + str(self.home) + '"')
        for tool in ["tccutil", "security", "defaults", "pgrep"]:
            fake = self.root / tool
            fake.write_text("#!/usr/bin/python3\n" +
                "import json,pathlib,sys\n" +
                "args=sys.argv[1:]\n" +
                "tool=" + repr(tool) + "\n" +
                "log=pathlib.Path(" + repr(str(self.log)) + ")\n" +
                "if tool!='pgrep':\n with log.open('a') as f:f.write(json.dumps([tool,args])+'\\n')\n" +
                "if tool=='pgrep':sys.exit(" + ("0" if self.running else "1") + ")\n" +
                "if tool=='tccutil':\n assert args==['reset','All','dev.iphoneduo.workbench'];sys.exit(0)\n" +
                "if tool=='security':\n assert args[0]=='delete-generic-password' and args[1]=='-s' and args[3]=='-a'\n assert args[2] in ['dev.chordesk.embedded-tailnet','dev.iphoneduo.remote-pairing']\n sys.exit(" + ("1" if self.keychain_failure else "0") + ")\n" +
                "pref=pathlib.Path(" + repr(str(self.preferences)) + ")\n" +
                "if tool=='defaults':\n assert args[1]=='dev.iphoneduo.workbench'\n if args[0]=='export':pathlib.Path(args[2]).write_bytes(pref.read_bytes())\n elif args[0]=='delete':pref.unlink()\n else:raise AssertionError(args)\n")
            fake.chmod(0o755)
            assert "/usr/bin/" + tool in text
            text = text.replace("/usr/bin/" + tool, str(fake))
        # A staged test must contain no actual permission or credential command.
        for tool in ["tccutil", "security", "defaults", "pgrep"]:
            assert "/usr/bin/" + tool not in text
        staged = self.root / "Maintenance.command"
        staged.write_text(text)
        return staged

    def run_action(self, choice, confirmation):
        script = self.stage_script()
        master, slave = pty.openpty()
        child = subprocess.Popen(["/bin/zsh", str(script)], stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = bytearray()
        try:
            os.write(master, (choice + "\n" + confirmation + "\n").encode())
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    output.extend(data)
                if child.poll() is not None and not readable:
                    break
            child.wait(timeout=2)
        finally:
            if child.poll() is None:
                child.kill(); child.wait()
            os.close(master)
        calls = [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
        return child.returncode, output.decode(errors="replace"), calls

    def assert_other_product_untouched(self):
        self.assertTrue(self.other.is_dir())
        self.assertEqual(self.other_preferences.read_bytes(), b"other product")

    def test_full_removal_moves_only_own_app_and_data_with_preference_backup(self):
        code, output, calls = self.run_action("5", "REMOVE")
        self.assertEqual(code, 0, output)
        self.assertFalse(self.app.exists()); self.assertFalse(self.data.exists())
        self.assertFalse(self.preferences.exists())
        backups = list((self.home / ".Trash").glob("*/preferences-backup.plist"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(plistlib.loads(backups[0].read_bytes())["fixture"], "keep a recoverable backup")
        self.assertIn(["tccutil", ["reset", "All", self.bundle]], calls)
        accounts = [x[1][-1] for x in calls if x[0] == "security"]
        self.assertIn("node-state-v1", accounts); self.assertIn("remembered-mac-v1", accounts)
        self.assert_other_product_untouched()

    def test_running_host_blocks_every_modifying_step(self):
        self.running = True
        code, output, calls = self.run_action("5", "REMOVE")
        self.assertNotEqual(code, 0, output); self.assertFalse(calls)
        self.assertTrue(self.app.exists()); self.assertTrue(self.preferences.exists())
        self.assert_other_product_untouched()

    def test_redirected_data_blocks_before_permission_or_keychain_changes(self):
        (self.data / "fixture.txt").unlink(); self.data.rmdir()
        elsewhere = self.root / "unrelated-data"; elsewhere.mkdir()
        (elsewhere / "keep.txt").write_text("do not follow")
        self.data.symlink_to(elsewhere, target_is_directory=True)
        code, output, calls = self.run_action("5", "REMOVE")
        self.assertNotEqual(code, 0, output); self.assertFalse(calls)
        self.assertEqual((elsewhere / "keep.txt").read_text(), "do not follow")

    def test_keychain_denial_does_not_remove_app_or_claim_complete(self):
        self.keychain_failure = True
        code, output, calls = self.run_action("5", "REMOVE")
        self.assertNotEqual(code, 0, output)
        self.assertNotIn("清理完成。", output)
        self.assertTrue(self.app.exists()); self.assertTrue(self.data.exists()); self.assertTrue(self.preferences.exists())
        self.assertNotIn(["defaults", ["delete", self.bundle]], calls)
        self.assert_other_product_untouched()

    def test_keep_data_uninstall_preserves_all_permissions_and_login(self):
        code, output, calls = self.run_action("4", "UNINSTALL")
        self.assertEqual(code, 0, output); self.assertFalse(calls)
        self.assertFalse(self.app.exists()); self.assertTrue(self.preferences.exists()); self.assertTrue(self.data.exists())
        self.assert_other_product_untouched()

    def test_wrong_confirmation_has_no_modifying_effect(self):
        code, output, calls = self.run_action("5", "NO")
        self.assertEqual(code, 0, output); self.assertFalse(calls)
        self.assertTrue(self.app.exists()); self.assertTrue(self.preferences.exists())

    def test_first_trash_use_creates_private_folder_without_touching_other_data(self):
        (self.home / ".Trash").rmdir()
        code, output, calls = self.run_action("4", "UNINSTALL")
        self.assertEqual(code, 0, output); self.assertFalse(calls)
        self.assertEqual((self.home / ".Trash").stat().st_mode & 0o777, 0o700)
        self.assert_other_product_untouched()


if __name__ == "__main__":
    unittest.main()
