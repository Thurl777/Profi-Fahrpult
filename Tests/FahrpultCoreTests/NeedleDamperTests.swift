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

    /// Zeit, bis die Nadel `share` des Wegs von `start` nach `end` zurückgelegt hat
    private func time(from start: Double, to end: Double, delay: Double, share: Double = 0.95) -> Double {
        var damper = NeedleDamper(value: start, delay: delay)
        damper.target = end
        var t = 0.0
        while abs(damper.value - start) < share * abs(end - start) && t < 60 {
            damper.advance(by: 1 / 60)
            t += 1 / 60
        }
        return t
    }

    func testGlidesMonotonicallyWithoutOvershoot() {
        var damper = NeedleDamper(value: 0, delay: 1)
        damper.target = 1
        let values = run(&damper, seconds: 2)
        XCTAssertGreaterThan(values[0], 0)
        XCTAssertLessThan(values[0], 0.01, "springt nicht sofort")
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b)
            XCTAssertLessThanOrEqual(b, 1)
        }
        XCTAssertTrue(damper.isSettled)
        XCTAssertEqual(damper.value, 1)
    }

    func testStartsSluggishly() {
        // Wie eine Lok: Die Beschleunigung baut sich erst auf, die Nadel ist am Anfang deutlich langsamer
        var damper = NeedleDamper(value: 0, delay: 2)
        damper.target = 1
        _ = run(&damper, seconds: 0.1)
        let early = damper.velocity
        _ = run(&damper, seconds: 0.4)
        let later = damper.velocity
        XCTAssertGreaterThan(early, 0)
        XCTAssertLessThan(early, later * 0.25)
    }

    func testFullSweepTakesRoughlyDelay() {
        var damper = NeedleDamper(value: 0, delay: 2)
        damper.target = 1
        _ = run(&damper, seconds: 1)
        XCTAssertLessThan(damper.value, 0.7, "nach der halben Zeit noch unterwegs")
        _ = run(&damper, seconds: 0.9)
        XCTAssertGreaterThan(damper.value, 0.97)
        _ = run(&damper, seconds: 0.5)
        XCTAssertTrue(damper.isSettled)
    }

    func testDurationDependsOnSizeOfChange() {
        // 0 auf halbe Geschwindigkeit dauert nicht so lange wie 0 auf Höchstgeschwindigkeit
        for delay in [1.0, 2.0, 5.0] {
            let half = time(from: 0, to: 0.5, delay: delay)
            let full = time(from: 0, to: 1, delay: delay)
            XCTAssertLessThan(half, full * 0.6, "Verzögerung \(delay)")
            XCTAssertGreaterThan(half, full * 0.4, "Verzögerung \(delay)")
            let small = time(from: 0, to: 0.1, delay: delay)
            XCTAssertLessThan(small, half * 0.6, "Verzögerung \(delay)")
        }
    }

    func testAcceleratesMoreSlowlyAtHighSpeed() {
        // Leistungsgrenze: die obere Hälfte des Tachos dauert länger als die untere
        let lower = time(from: 0, to: 0.5, delay: 2)
        let upper = time(from: 0.5, to: 1, delay: 2)
        XCTAssertGreaterThan(upper, lower * 1.1)
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

    func testNoOvershootWhenTargetChangesWhileMoving() {
        var damper = NeedleDamper(value: 0, delay: 2)
        damper.target = 1
        _ = run(&damper, seconds: 0.8)
        let newTarget = damper.value + 0.02
        damper.target = newTarget
        let values = run(&damper, seconds: 3)
        XCTAssertLessThanOrEqual(values.max() ?? 0, newTarget)
        XCTAssertTrue(damper.isSettled)
        XCTAssertEqual(damper.value, newTarget)
    }

    func testFollowsStepwiseTargetMonotonically() {
        // Schieberegler wird Fahrstufe für Fahrstufe hochgezogen
        var damper = NeedleDamper(value: 0, delay: 2)
        var values: [Double] = []
        for step in 1...126 {
            damper.target = Double(step) / 126
            values += run(&damper, seconds: 1.0 / 30)
        }
        values += run(&damper, seconds: 3)
        for (a, b) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b)
        }
        XCTAssertTrue(damper.isSettled)
        XCTAssertEqual(damper.value, 1)
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
