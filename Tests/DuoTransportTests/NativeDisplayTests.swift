import XCTest
@testable import DuoWorkbench

final class NativeDisplayTests: XCTestCase {
    func testBuiltInExpandedScalingFamilyIsAcceptedButExternalCustomIsNot() {
        let current = NativeDisplayMode(id: 72, width: 2056, height: 1329, pixelWidth: 4112, pixelHeight: 2658, refresh: 120, safe: true)
        var sibling = current; sibling.id = 73; sibling.refresh = 60
        XCTAssertTrue(NativeDisplaySystem.supportsBaseline(current, standard: [], expanded: [current, sibling], builtIn: true))
        XCTAssertFalse(NativeDisplaySystem.supportsBaseline(current, standard: [], expanded: [current, sibling], builtIn: false))
        XCTAssertFalse(NativeDisplaySystem.supportsBaseline(current, standard: [], expanded: [current], builtIn: true))
        sibling.safe = false
        XCTAssertFalse(NativeDisplaySystem.supportsBaseline(current, standard: [], expanded: [current, sibling], builtIn: true))
        XCTAssertTrue(NativeDisplaySystem.supportsBaseline(current, standard: [current], expanded: [current], builtIn: false))
    }
    func testUnlistedBaselineCannotBeChangedOrJournaled() async throws {
        let (bridge, fake, defaults) = fixture()
        await fake.setRestorationSupported(false)
        let state = try await bridge.state(displayID: 1)
        XCTAssertTrue(state.options.isEmpty)
        do { try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true); XCTFail() } catch {}
        let history = await fake.history
        XCTAssertTrue(history.isEmpty)
        XCTAssertNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
    }
    func testDefaultIsExact1600AndPrefersHiDPIAtSameResolution() {
        var display = NativeFixture.initial
        display.modes.append(.init(id: 6, width: 1600, height: 900, pixelWidth: 3200, pixelHeight: 1800, refresh: 60, safe: true))
        let selected = NativeDisplayBridge.presets(display).first { $0.0 == "fit" }!.2
        XCTAssertEqual(selected.id, 6)
    }
    func testStandard1600IsAvailableWithoutThirdPartyHiDPI() {
        let selected = NativeDisplayBridge.presets(NativeFixture.initial).first { $0.0 == "fit" }!.2
        XCTAssertEqual(selected.width, 1600); XCTAssertEqual(selected.height, 900)
        XCTAssertFalse(selected.hiDPI)
    }
    func testUnsafeAndDistortedModesCannotBecomeDefault() {
        var display = NativeFixture.initial
        display.modes[1].safe = false
        display.modes.append(.init(id: 8, width: 1600, height: 1000, pixelWidth: 1600, pixelHeight: 1000, refresh: 60, safe: true))
        let selected = NativeDisplayBridge.presets(display).first { $0.0 == "fit" }!.2
        XCTAssertNotEqual(selected.id, 2); XCTAssertNotEqual(selected.id, 8)
    }
    func testNonWidescreenKeepsAspectRatioAndLabelsActualFallback() {
        let mode = NativeDisplayMode(id: 9, width: 1600, height: 1034, pixelWidth: 3200, pixelHeight: 2068, refresh: 60, safe: true)
        let display = NativeDisplaySnapshot(uuid: "test", id: 1, current: mode, modes: [mode, NativeFixture.initial.modes[1]])
        let selected = NativeDisplayBridge.presets(display).first!
        XCTAssertEqual(selected.2.height, 1034); XCTAssertTrue(selected.1.contains("保持比例"))
    }
    func testRetainsRefreshRateWhenExactModeSupportsIt() {
        var display = NativeFixture.initial
        display.current.refresh = 120
        var mode = display.modes[1]; mode.id = 12; mode.refresh = 120; display.modes.append(mode)
        XCTAssertEqual(NativeDisplayBridge.presets(display).first!.2.refresh, 120)
    }
    func testSessionRestoresModesBeforeOriginalVerticalLayout() async throws {
        let (bridge, fake, defaults) = fixture()
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        try await bridge.apply(displayID: 1, choice: "larger", sessionScoped: true)
        let errors = await bridge.restoreSessionModes()
        let current = await fake.display.current
        let history = await fake.history
        XCTAssertTrue(errors.isEmpty); XCTAssertEqual(current.id, 1)
        XCTAssertEqual(Array(history.suffix(2)), ["mode:1", "layout:0,0;0,1080"])
        XCTAssertNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
    }
    func testFailedModeKeepsBaselineAndRetryAfterRestartRestores() async throws {
        let (bridge, fake, defaults) = fixture()
        await fake.setFailure(true)
        do { try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true); XCTFail() } catch {}
        XCTAssertNotNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
        await fake.setFailure(false)
        let recovered = NativeDisplayBridge(defaults: defaults, access: fake.access)
        let errors = await recovered.restoreSessionModes()
        XCTAssertTrue(errors.isEmpty); XCTAssertNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
    }
    func testLayoutFailureRetainsAllModesUntilWholeRestorationSucceeds() async throws {
        let (bridge, fake, defaults) = fixture()
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        await fake.setLayoutFailure(true)
        let errors = await bridge.restoreSessionModes()
        XCTAssertFalse(errors.isEmpty); XCTAssertNotNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
        await fake.setLayoutFailure(false)
        let recovered = NativeDisplayBridge(defaults: defaults, access: fake.access)
        let retry = await recovered.restoreSessionModes()
        XCTAssertTrue(retry.isEmpty); XCTAssertNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
    }
    func testSessionBaselineDoesNotReplaceManualOriginal() async throws {
        let (bridge, fake, _) = fixture()
        try await bridge.apply(displayID: 1, choice: "fit")
        try await bridge.apply(displayID: 1, choice: "larger", sessionScoped: true)
        _ = await bridge.restoreSessionModes()
        let baseline = await fake.display.current
        XCTAssertEqual(baseline.id, 2)
        try await bridge.apply(displayID: 1, choice: "restore")
        let original = await fake.display.current
        XCTAssertEqual(original.id, 1)
    }
    func testMissingOriginalModeDoesNotClearRestoreRecord() async throws {
        let (bridge, fake, defaults) = fixture()
        try await bridge.apply(displayID: 1, choice: "fit", sessionScoped: true)
        await fake.removeOriginal()
        let errors = await bridge.restoreSessionModes()
        XCTAssertFalse(errors.isEmpty); XCTAssertNotNil(defaults.data(forKey: "ChordeskNativeSessionDisplay"))
    }
    private func fixture() -> (NativeDisplayBridge, NativeFixture, UserDefaults) {
        let name = "NativeDisplay-\(UUID())", fake = NativeFixture()
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (NativeDisplayBridge(defaults: defaults, access: fake.access), fake, defaults)
    }
}
private actor NativeFixture {
    static let initial: NativeDisplaySnapshot = {
        let modes: [NativeDisplayMode] = [(Int32(1),1920,1080), (2,1600,900), (3,1024,576), (4,800,450)].map { id,w,h in
            .init(id: id,width:w,height:h,pixelWidth:w,pixelHeight:h,refresh:60,safe:true)
        }
        return .init(uuid: "stable-display", id: 1, current: modes[0], modes: modes)
    }()
    var display = initial
    var history: [String] = []
    private var fail = false, failLayout = false
    nonisolated var access: NativeDisplayAccess {
        .init(snapshot: { _ in await self.display }, resolve: { _ in await self.display }, set: { _, mode in try await self.set(mode) },
              arrangement: .init(capture: { [.init(uuid: "upper",x:0,y:0),.init(uuid: "lower",x:0,y:1080)] }, restore: { value in try await self.restore(value) }))
    }
    func set(_ mode: NativeDisplayMode) throws {
        if fail { throw NSError(domain: "mode failure", code: 1) }
        display.current = mode; history.append("mode:\(mode.id)")
    }
    func restore(_ value: [DisplayPlacement]) throws {
        if failLayout { throw NSError(domain: "layout failure", code: 1) }
        history.append("layout:" + value.map { "\($0.x),\($0.y)" }.joined(separator: ";"))
    }
    func setFailure(_ value: Bool) { fail = value }
    func setRestorationSupported(_ value: Bool) { display.restorationSupported = value }
    func setLayoutFailure(_ value: Bool) { failLayout = value }
    func removeOriginal() { display.modes.removeAll { $0.id == 1 } }
}
