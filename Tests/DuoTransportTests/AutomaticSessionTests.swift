import XCTest
@testable import DuoWorkbench

final class AutomaticSessionTests: XCTestCase {
    func testRearSwitchLeavesKeyboardStateUntouched() {
        var grip = GripInputState()
        _ = grip.configure(defaultMode: .keyboard, activation: .momentary, trigger: .touch)
        _ = grip.outerContacts(2)
        XCTAssertEqual(grip.requestedMode, .keyboard)
        XCTAssertEqual(grip.requestedFrontMode, .trackpad)
        _ = grip.outerContacts(0)
        XCTAssertEqual(grip.requestedMode, .keyboard)
        XCTAssertEqual(grip.requestedFrontMode, .direct)
    }

    func testRearSwitchConsumesDelayedKeyboardSuggestionButNewClickStillWorks() {
        var policy = AutomaticKeyboardPolicy()
        let old = LANTextFocus(id: "field", editable: true, secure: false, requestID: 8)
        XCTAssertNil(policy.mode(for: old, frontContacts: 0, rearContacts: 1))
        policy.suppress(through: 10)
        XCTAssertNil(policy.mode(for: old, frontContacts: 0, rearContacts: 0))
        let new = LANTextFocus(id: "field", editable: true, secure: false, requestID: 11)
        XCTAssertEqual(policy.mode(for: new, frontContacts: 0, rearContacts: 0), .keyboard)
        XCTAssertNil(policy.mode(for: new, frontContacts: 0, rearContacts: 0))
    }

    func testFocusChangeWithoutNewClickDoesNotReopenKeyboard() {
        var policy = AutomaticKeyboardPolicy()
        let text = LANTextFocus(id: "field", editable: true, secure: false, requestID: 1)
        XCTAssertEqual(policy.mode(for: text, frontContacts: 0, rearContacts: 0), .keyboard)
        let other = LANTextFocus(id: "other-field", editable: true, secure: false, requestID: 1)
        XCTAssertNil(policy.mode(for: other, frontContacts: 0, rearContacts: 0))
        policy.suppress(through: 2) // Explicit manual close also consumes late responses.
        XCTAssertNil(policy.mode(for: .init(id: "field", editable: true, secure: false, requestID: 2), frontContacts: 0, rearContacts: 0))
    }

    func testFitAndLaterChangesRestoreConnectionBaseline() async throws {
        let fake = FakeDisplayCLI()
        let (bridge, defaults) = bridge(fake)
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        try await bridge.apply(displayID: 1, choice: "larger", sessionScoped: true)
        let errors = await bridge.restoreSessionModes()
        let current = await fake.current
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(current, 1)
        XCTAssertTrue((defaults.dictionary(forKey: "DuoSessionDisplayModes") ?? [:]).isEmpty)
    }

    func testSessionBaselineIsCurrentModeNotHistoricalManualOriginal() async throws {
        let fake = FakeDisplayCLI()
        let (bridge, _) = bridge(fake)
        try await bridge.apply(displayID: 1, choice: "space") // Historical manual original = 1920.
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        let errors = await bridge.restoreSessionModes()
        let current = await fake.current
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(current, 4) // Return to 1600, the actual pre-connection mode.
        try await bridge.apply(displayID: 1, choice: "restore")
        let original = await fake.current
        XCTAssertEqual(original, 1)
    }

    func testDisconnectDuringFitWaitsThenRestoresWithoutLosingBaseline() async throws {
        let fake = FakeDisplayCLI(blockFirstSet: true)
        let (bridge, _) = bridge(fake)
        let fit = Task { try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true) }
        await fake.waitUntilSetStarted()
        let disconnect = Task { await bridge.restoreSessionModes() }
        await fake.finishBlockedSet()
        try await fit.value
        let errors = await disconnect.value
        let history = await fake.history
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(history, [4, 1])
    }

    func testFailedRestorePersistsForNextLaunchRetry() async throws {
        let fake = FakeDisplayCLI()
        let (first, defaults) = bridge(fake)
        try await first.apply(displayID: 1, choice: "fit", sessionScoped: true)
        await fake.setOriginalAvailable(false)
        let errors = await first.restoreSessionModes()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertNotNil(defaults.dictionary(forKey: "DuoSessionDisplayModes")?[FakeDisplayCLI.uuid])
        await fake.setOriginalAvailable(true)
        let recovered = BetterDisplayBridge(defaults: defaults, arrangement: .none, command: { try await fake.run($0) })
        let retry = await recovered.restoreSessionModes()
        let current = await fake.current
        XCTAssertTrue(retry.isEmpty)
        XCTAssertEqual(current, 1)
    }

    func testAlreadyFitStillRecordsBaselineBeforeLaterAdjustment() async throws {
        let fake = FakeDisplayCLI(current: 4)
        let (bridge, _) = bridge(fake)
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        try await bridge.apply(displayID: 1, choice: "larger", sessionScoped: true)
        _ = await bridge.restoreSessionModes()
        let current = await fake.current
        XCTAssertEqual(current, 4)
    }

    func testLayoutRestoresAfterModesAndDoesNotLoseVerticalArrangement() async throws {
        let fake = FakeDisplayCLI()
        let suite = "Layout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let baseline = [DisplayPlacement(uuid: "upper", x: 0, y: 0), DisplayPlacement(uuid: "lower", x: 0, y: 1200)]
        let observer = LayoutObserver()
        let access = DisplayArrangementAccess(capture: { baseline }, restore: { value in
            let mode = await fake.current
            await observer.record(value, mode: mode)
        })
        let bridge = BetterDisplayBridge(defaults: defaults, arrangement: access, command: { try await fake.run($0) })
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        try await bridge.apply(displayID: 1, choice: "largest", sessionScoped: true)
        XCTAssertNotNil(defaults.data(forKey: "DuoSessionDisplayLayout"))
        let errors = await bridge.restoreSessionModes()
        let restored = await observer.placements, mode = await observer.mode
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(restored, baseline)
        XCTAssertEqual(mode, 1, "Restore all logical resolutions before applying original positions.")
        XCTAssertNil(defaults.data(forKey: "DuoSessionDisplayLayout"))
    }

    func testFailedLayoutRemainsAvailableForNextLaunchRetry() async throws {
        let fake = FakeDisplayCLI()
        let suite = "LayoutRetry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let baseline = [DisplayPlacement(uuid: "main", x: 0, y: 0)]
        let first = BetterDisplayBridge(defaults: defaults, arrangement: .init(capture: { baseline }, restore: { _ in
            throw NSError(domain: "offline-display", code: 1)
        }), command: { try await fake.run($0) })
        try await first.apply(displayID: 1, choice: "fit", sessionScoped: true)
        let errors = await first.restoreSessionModes()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertNotNil(defaults.data(forKey: "DuoSessionDisplayLayout"))
        let observer = LayoutObserver()
        let second = BetterDisplayBridge(defaults: defaults, arrangement: .init(capture: { [] }, restore: { value in
            let mode = await fake.current
            await observer.record(value, mode: mode)
        }), command: { try await fake.run($0) })
        let retry = await second.restoreSessionModes()
        let restored = await observer.placements
        XCTAssertTrue(retry.isEmpty); XCTAssertEqual(restored, baseline)
    }

    private func bridge(_ fake: FakeDisplayCLI) -> (BetterDisplayBridge, UserDefaults) {
        let suite = "DuoTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (BetterDisplayBridge(defaults: defaults, arrangement: .none, command: { try await fake.run($0) }), defaults)
    }
}

/// Exercises real parsing, preset selection, persistence and operation ordering;
/// it never invokes BetterDisplay or changes a physical display.
private actor FakeDisplayCLI {
    static let uuid = "A975366A-A26A-4E8B-9322-6C94CDBFC56F"
    var current: Int
    var history: [Int] = []
    private var originalAvailable = true
    private var blockFirstSet: Bool
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?
    init(current: Int = 1, blockFirstSet: Bool = false) { self.current = current; self.blockFirstSet = blockFirstSet }
    func setOriginalAvailable(_ value: Bool) { originalAvailable = value }
    func waitUntilSetStarted() async { if !started { await withCheckedContinuation { startWaiter = $0 } } }
    func finishBlockedSet() { finishWaiter?.resume(); finishWaiter = nil }
    func run(_ args: [String]) async throws -> String {
        if args == ["get", "-identifiers"] {
            return "[{\"displayID\":1,\"deviceType\":\"Display\",\"UUID\":\"\(Self.uuid)\"}]"
        }
        if args.first == "set" {
            guard let raw = args.last?.split(separator: "=").last, let mode = Int(raw) else { throw NSError(domain: "test", code: 1) }
            if blockFirstSet {
                blockFirstSet = false; started = true; startWaiter?.resume(); startWaiter = nil
                await withCheckedContinuation { finishWaiter = $0 }
            }
            current = mode; history.append(mode); return "OK"
        }
        return [(1, "1920x1200"), (2, "1280x800"), (3, "1024x640"), (4, "1600x1000"), (5, "800x500"), (6, "640x400")]
            .filter { originalAvailable || $0.0 != 1 }
            .map { "\($0.0) - \($0.1) HiDPI 60Hz" + ($0.0 == current ? " Current" : "") }.joined(separator: "\n")
    }
}

private actor LayoutObserver {
    var placements: [DisplayPlacement] = []
    var mode = 0
    func record(_ value: [DisplayPlacement], mode: Int) { placements = value; self.mode = mode }
}
