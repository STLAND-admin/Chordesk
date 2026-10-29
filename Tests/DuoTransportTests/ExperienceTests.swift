import XCTest
import CoreGraphics
@testable import DuoWorkbench

final class ExperienceTests: XCTestCase {
    func testOverviewShortcutBalancesControlAndFollowingTapHasNoModifiers() throws {
        let factory = RemoteEventFactory()
        let keys = try XCTUnwrap(factory.keyboard(code: 126, modifiers: 8))
        XCTAssertEqual(keys.map { $0.type }, [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(keys.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [59, 126, 126, 59])
        XCTAssertTrue(keys[1].flags.contains(.maskControl))
        XCTAssertEqual(keys.last?.flags, [])
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved] {
            let event = try XCTUnwrap(factory.mouse(type, at: .zero))
            XCTAssertEqual(event.type, type)
            XCTAssertEqual(event.flags, [], "A remote left click must never become Control-click.")
        }
        XCTAssertEqual(factory.scroll(dy: 40)?.flags, [])
        let escape = try XCTUnwrap(factory.keyboard(code: 53, modifiers: 0))
        XCTAssertEqual(escape.map { $0.flags }, [[], []])
    }
    func testCombinedShortcutReleasesAllModifiersAndInvalidBatchCreatesNothing() throws {
        let factory = RemoteEventFactory()
        let keys = try XCTUnwrap(factory.keyboard(code: 0, modifiers: 15))
        XCTAssertEqual(keys.count, 10)
        XCTAssertEqual(keys.filter { $0.type == .keyDown }.count, 1)
        XCTAssertEqual(keys.filter { $0.type == .keyUp }.count, 1)
        XCTAssertEqual(keys.last?.flags, [])
        XCTAssertNil(factory.keyboard(code: 0, modifiers: 16))
    }
    func testHighQualityKeepsHiDPIPixelsInsteadOfLogical1280Limit() {
        XCTAssertEqual(LANVideoQuality.sharp.captureSize(pixels: CGSize(width: 2560, height: 1440)), CGSize(width: 2560, height: 1440))
        XCTAssertEqual(LANVideoQuality.ultra.captureSize(pixels: CGSize(width: 7680, height: 4320)), CGSize(width: 3840, height: 2160))
        XCTAssertGreaterThan(LANVideoQuality.sharp.jpegQuality, 0.55)
        XCTAssertEqual(LANVideoQuality.efficient.captureSize(pixels: CGSize(width: 1920, height: 1080)).width, 1280)
    }
    func testActualVideoPayloadRateIsMeasuredAndFallsToZeroWhenIdle() {
        var meter = VideoTrafficMeter()
        meter.record(bytes: 500_000, now: 10)
        meter.record(bytes: 500_000, now: 10.5)
        XCTAssertNil(meter.sample(now: 10.9))
        let result = meter.sample(now: 11)!
        XCTAssertEqual(result.mbps, 8, accuracy: 0.001)
        XCTAssertEqual(result.fps, 2)
        XCTAssertEqual(meter.sample(now: 12)!.mbps, 0)
    }
    func testHighFrameRateProfilesBoundPixelWorkAndDoNotUpscale() {
        let source = CGSize(width: 7680, height: 4320)
        let baseline = LANVideoQuality.sharp.captureSize(pixels: source)
        let baselineWork = baseline.width * baseline.height * CGFloat(LANVideoQuality.sharp.framesPerSecond)
        for quality in [LANVideoQuality.responsive60, .experimental120, .experimental144] {
            let size = quality.captureSize(pixels: source)
            XCTAssertLessThan(size.width * size.height * CGFloat(quality.framesPerSecond), baselineWork)
            XCTAssertEqual(size.width / size.height, source.width / source.height, accuracy: 0.01)
            XCTAssertEqual(Int(size.width) % 2, 0)
            XCTAssertEqual(Int(size.height) % 2, 0)
            XCTAssertEqual(quality.captureSize(pixels: CGSize(width: 320, height: 180)), CGSize(width: 320, height: 180))
        }
    }
    func testQualityNegotiationDoesNotSendNewProfilesToOldHost() throws {
        let oldStatus = LANStatus(name: "Old Mac", width: 1920, height: 1080, canControl: false, message: "", videoQuality: "sharp")
        let decoded = try JSONDecoder().decode(LANStatus.self, from: JSONEncoder().encode(oldStatus))
        XCTAssertEqual(LANVideoQuality.supported(by: decoded.supportedVideoQualities), [.efficient, .sharp, .ultra])
        XCTAssertEqual(LANVideoQuality.supported(by: ["future-codec", "responsive60", "sharp", "sharp"]), [.sharp, .responsive60])
        XCTAssertEqual(LANVideoQuality.supported(by: []), [])
        XCTAssertNil(LANVideoQuality(rawValue: "arbitrary-frame-rate"))
    }
    func testModifierCombinationIsOneShotAndUnicodeDoesNotBecomeShortcut() {
        var modifiers = ShortcutModifiers()
        modifiers.toggle(8); modifiers.toggle(4); modifiers.toggle(2)
        let command = modifiers.shortcut(for: "A")
        XCTAssertEqual(command?.key, "a"); XCTAssertEqual(command?.flags, 14)
        XCTAssertEqual(modifiers.flags, 0)
        modifiers.toggle(2)
        let zoom = modifiers.shortcut(for: "+")
        XCTAssertEqual(zoom?.key, "="); XCTAssertEqual(zoom?.flags, 3)
        modifiers.toggle(2)
        XCTAssertNil(modifiers.shortcut(for: "你好"))
        XCTAssertEqual(modifiers.flags, 0)
        modifiers.toggle(4); modifiers.toggle(4)
        XCTAssertEqual(modifiers.flags, 0)
    }
    func testMagnifierAvoidsFingerAndStaysWithinSystemSafeRectangle() {
        let safe = CGRect(x: 20, y: 40, width: 800, height: 700)
        let point = CGPoint(x: 400, y: 500)
        let lens = MagnifierGeometry.frame(around: point, within: safe)
        XCTAssertTrue(safe.contains(lens)); XCTAssertLessThan(lens.maxY, point.y)
        for point in [safe.origin, CGPoint(x: safe.maxX, y: safe.maxY)] {
            XCTAssertTrue(safe.contains(MagnifierGeometry.frame(around: point, within: safe)))
        }
    }
}
