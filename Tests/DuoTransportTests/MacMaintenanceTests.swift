import XCTest
import Security
@testable import DuoWorkbench

final class MacMaintenanceTests: XCTestCase {
    func testKeychainErrorsAreClassifiedWithoutTreatingUnrelatedErrorsAsCredentials() throws {
        for operation in ["read", "write", "delete"] {
            let failure = try XCTUnwrap(MacKeychainFailure.parse("Keychain \(operation) failed (-25293)"))
            XCTAssertEqual(failure.status, errSecAuthFailed)
            XCTAssertTrue(failure.canAuthorize)
        }
        XCTAssertTrue(try XCTUnwrap(MacKeychainFailure.parse("Keychain read failed (-25308)")).canAuthorize)
        for text in [nil, "Network failed (-25293)", "Keychain read failed (2147483648)",
                     "Keychain read failed (-25293) extra", "https://example.com/Keychain read failed (-25293)"] {
            XCTAssertNil(MacKeychainFailure.parse(text))
        }
    }

    func testRepairOnlyTargetsTheDailyMacAppNotQAOrAnotherProduct() {
        XCTAssertEqual(ChordeskMaintenanceScope.permissionArguments(bundleID: "dev.iphoneduo.workbench"),
                       ["reset", "All", "dev.iphoneduo.workbench"])
        for identifier in [nil, "", "All", "com.apple.Terminal", "dev.chordesk.firstrun.qtest", "dev.portalatlas.app"] {
            XCTAssertNil(ChordeskMaintenanceScope.permissionArguments(bundleID: identifier))
        }
        XCTAssertEqual(ChordeskMaintenanceScope.tailnetQuery[kSecAttrService as String] as? String, "dev.chordesk.embedded-tailnet")
        XCTAssertEqual(ChordeskMaintenanceScope.tailnetQuery[kSecAttrAccount as String] as? String, "node-state-v1")
        XCTAssertNil(ChordeskMaintenanceScope.tailnetQuery[kSecAttrAccess as String], "Never widen the old credential ACL")
    }

    func testReadOnlyHelperAcceptsNoArbitraryTargetsOrDestructiveAction() {
        let argument = MacKeychainAuthorizationHelper.argument
        XCTAssertTrue(MacKeychainAuthorizationHelper.accepts(arguments: ["app", argument], bundleID: ChordeskMaintenanceScope.bundleID))
        for arguments in [["app"], ["app", argument, "another-service"], ["app", "--delete-keychain"]] {
            XCTAssertFalse(MacKeychainAuthorizationHelper.accepts(arguments: arguments, bundleID: ChordeskMaintenanceScope.bundleID))
        }
        XCTAssertFalse(MacKeychainAuthorizationHelper.accepts(arguments: ["app", argument], bundleID: "dev.chordesk.firstrun.qtest"))
        XCTAssertTrue(MacKeychainAuthorizationReply(status: errSecSuccess).canRetry)
        XCTAssertTrue(MacKeychainAuthorizationReply(status: errSecItemNotFound).canRetry)
        for status in [errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecParam] {
            XCTAssertFalse(MacKeychainAuthorizationReply(status: status).canRetry)
        }
    }

    func testMaintenanceToolHasReadOnlyPlanAndRefusesUnattendedMutation() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repository.appendingPathComponent("scripts/Chordesk-Maintenance.command")
        func run(_ arguments: [String]) throws -> (Int32, String) {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path] + arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output; process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        let plan = try run(["--plan"])
        XCTAssertEqual(plan.0, 0)
        XCTAssertTrue(plan.1.contains("tccutil reset All dev.iphoneduo.workbench"))
        XCTAssertTrue(plan.1.contains("dev.chordesk.embedded-tailnet / node-state-v1"))
        let unattended = try run([])
        XCTAssertEqual(unattended.0, 2)
        XCTAssertTrue(unattended.1.contains("交互式终端"))
        XCTAssertEqual(try run(["--uninstall", "--yes"]).0, 2)
    }
}
