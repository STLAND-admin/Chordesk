import XCTest
@testable import ChordeskHost

final class PermissionAndUninstallTests: XCTestCase {
    func testThreePermissionStatesIncludeCachedGrantAndCachedDenial() {
        XCTAssertEqual(HostPermissionState.resolve(current: false, fresh: false, requestedThisLaunch: false), .notGranted)
        XCTAssertEqual(HostPermissionState.resolve(current: false, fresh: true, requestedThisLaunch: false), .restartRequired)
        XCTAssertEqual(HostPermissionState.resolve(current: true, fresh: true, requestedThisLaunch: false), .ready)
        XCTAssertEqual(HostPermissionState.resolve(current: true, fresh: false, requestedThisLaunch: false), .notGranted)
        XCTAssertEqual(HostPermissionState.resolve(current: true, fresh: true, requestedThisLaunch: true), .restartRequired)
        XCTAssertEqual(HostPermissionState.resolve(current: false, fresh: false, requestedThisLaunch: true), .notGranted)
        XCTAssertEqual(HostPermissionState.resolve(current: false, fresh: nil, requestedThisLaunch: false), .notGranted)
        XCTAssertEqual(HostPermissionState.resolve(current: true, fresh: nil, requestedThisLaunch: false), .ready)
        XCTAssertTrue(HostPermissionProbe.accepts(arguments: ["app", HostPermissionProbe.argument]))
        XCTAssertFalse(HostPermissionProbe.accepts(arguments: ["app", HostPermissionProbe.argument, "other-app"]))
    }

    func testUninstallerCannotSelectOtherAppsArbitraryModesOrPaths() {
        let args = ["app", MacUninstallHelper.argument, "123", "full"]
        XCTAssertEqual(MacUninstallHelper.mode(arguments: args, bundleID: ChordeskMaintenanceScope.bundleID), .full)
        XCTAssertNil(MacUninstallHelper.mode(arguments: args, bundleID: "dev.portalatlas.app"))
        for bad in [["app"], ["app", MacUninstallHelper.argument, "1", "full"],
                    ["app", MacUninstallHelper.argument, "123", "/Applications/Other.app"], args + ["--yes"]] {
            XCTAssertNil(MacUninstallHelper.mode(arguments: bad, bundleID: ChordeskMaintenanceScope.bundleID))
        }
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertTrue(MacUninstallHelper.isStandardInstallation(URL(fileURLWithPath: "/Applications/Chordesk.app"), home: home))
        XCTAssertTrue(MacUninstallHelper.isStandardInstallation(home.appendingPathComponent("Applications/Chordesk.app"), home: home))
        for path in ["/Volumes/Chordesk/Chordesk.app", "/Applications/Other.app", "/private/tmp/Chordesk.app"] {
            XCTAssertFalse(MacUninstallHelper.isStandardInstallation(URL(fileURLWithPath: path), home: home))
        }
    }

    func testNativeUninstallRunnerDeliversOnlyConfirmedChoiceThroughPTY() throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("Chordesk-uninstall-fixture-\(UUID()).zsh")
        defer { try? FileManager.default.removeItem(at: fixture) }
        // No real maintenance action, filesystem deletion, TCC or Keychain call.
        try "[[ -t 0 && -t 1 ]] || exit 9\nprint -n -- '选择：'\nIFS= read -r choice\nIFS= read -r word\nprint -r -- \"fixture:$choice:$word\"\nexit 7\n".write(to: fixture, atomically: true, encoding: .utf8)
        for (mode, expected) in [(MacUninstallMode.appOnly, "fixture:4:UNINSTALL"), (.full, "fixture:5:REMOVE")] {
            let result = try MacUninstallHelper.runBackend(script: fixture, mode: mode)
            XCTAssertEqual(result.0, 7, "Nonzero backend status must never look successful")
            XCTAssertTrue(result.1.contains(expected), result.1)
        }
    }

    func testHelperLocationAcceptsSystemTmpAliasButRejectsPrefixLookalikes() {
        let id = UUID().uuidString
        let helper = URL(fileURLWithPath: "/private/tmp/ChordeskUninstaller.\(id)/ChordeskUninstaller.app")
        // Foundation resolves aliases of existing paths, as in the real copy.
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true))
        defer { try? FileManager.default.removeItem(at: helper.deletingLastPathComponent()) }
        for root in ["/tmp", "/private/tmp"] {
            XCTAssertTrue(MacUninstallHelper.isHelperLocation(URL(fileURLWithPath: "\(root)/ChordeskUninstaller.\(id)/ChordeskUninstaller.app")), root)
        }
        for path in ["/private/tmp/ChordeskUninstaller.bad/ChordeskUninstaller.app",
                     "/private/tmp/ChordeskUninstaller.\(id)/nested/ChordeskUninstaller.app",
                     "/private/tmp/ChordeskUninstaller.\(id)/Other.app",
                     "/private/tmp/Other.\(id)/ChordeskUninstaller.app",
                     "/Applications/ChordeskUninstaller.\(id)/ChordeskUninstaller.app"] {
            XCTAssertFalse(MacUninstallHelper.isHelperLocation(URL(fileURLWithPath: path)), path)
        }
    }

    func testPreflightIsNonDestructiveAndRefusalIsAnExplicitReply() throws {
        XCTAssertEqual(MacUninstallHelper.mode(arguments: ["app", MacUninstallHelper.probeArgument, "123", "app-only"], bundleID: ChordeskMaintenanceScope.bundleID), .appOnly)
        let refusal = MacUninstallHelper.Reply(ready: false, refusal: .helperLocation)
        XCTAssertEqual(try JSONDecoder().decode(MacUninstallHelper.Reply.self, from: JSONEncoder().encode(refusal)), refusal)
        XCTAssertTrue(MacUninstallHelper.Failure.refused(.parentProcess).localizedDescription.contains("parentProcess"))
        XCTAssertFalse(MacUninstallHelper.Failure.refused(.parentProcess).localizedDescription.contains("Applications"))
    }
}
