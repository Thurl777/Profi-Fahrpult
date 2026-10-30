import XCTest
@testable import FahrpultCore

final class NeedleDamperTests: XCTestCase {

    private func run(_ damper: inout NeedleDamper, seconds: Double, fps: Double = 60) -> [Double] {
        var values: [Double] = []
        for _ in 0..<Int(seconds * fps) {
            values.append(damper.advance(by: 1 / fps))
        }
        return values
    }

    func testGlidesMonotonicallyWithoutOvershoot() {
        var damper = NeedleDamper(value: 0, delay: 1)
        damper.target = 1
        let values = run(&damper, seconds: 2)
        XCTAssertGreaterThan(values[0], 0)
        XCTAssertLessThan(values[0], 0.1, "springt nicht sofort")
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b)
            XCTAssertLessThanOrEqual(b, 1)
        }
        XCTAssertTrue(damper.isSettled)
        XCTAssertEqual(damper.value, 1)
    }

    func testReachesTargetRoughlyAfterDelay() {
        var damper = NeedleDamper(value: 0, delay: 2)
        damper.target = 1
        _ = run(&damper, seconds: 1)
        XCTAssertLessThan(damper.value, 0.9, "nach der halben Verzögerung noch unterwegs")
        _ = run(&damper, seconds: 1)
        XCTAssertGreaterThan(damper.value, 0.97)
        _ = run(&damper, seconds: 1.5)
        XCTAssertTrue(damper.isSettled)
    }

    func testLongerDelayIsSlower() {
        var fast = NeedleDamper(value: 0, delay: 0.5)
        var slow = NeedleDamper(value: 0, delay: 3)
        fast.target = 1
        slow.target = 1
        _ = run(&fast, seconds: 0.5)
        _ = run(&slow, seconds: 0.5)
        XCTAssertGreaterThan(fast.value, slow.value)
    }

    func testGlidesDownwards() {
        var damper = NeedleDamper(value: 0.8, delay: 1)
        damper.target = 0.2
        let values = run(&damper, seconds: 2)
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertGreaterThanOrEqual(a, b)
            XCTAssertGreaterThanOrEqual(b, 0.2)
        }
        XCTAssertEqual(damper.value, 0.2)
    }

    func testJumpSetsValueImmediately() {
        var damper = NeedleDamper(value: 0, delay: 1)
        damper.target = 1
        damper.advance(by: 0.1)
        damper.jump(to: 0)
        XCTAssertTrue(damper.isSettled)
        XCTAssertEqual(damper.value, 0)
    }

    func testZeroDelayJumps() {
        var damper = NeedleDamper(value: 0, delay: 0)
        damper.target = 0.42
        XCTAssertEqual(damper.advance(by: 1 / 60), 0.42)
    }
}
