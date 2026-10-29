import XCTest
@testable import FahrpultCore

final class ContactSpeedMeasurerTests: XCTestCase {

    func testForwardPassComputesAverageSpeed() {
        // H0 (1:87), 50 cm je Abschnitt, 1 s je Abschnitt -> 0,5 m/s -> *3.6*87 = 156,6 km/h
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 50, distanceMiddleRightCm: 50, scale: .h0)
        XCTAssertNil(measurer.occupied(.left, at: 0))
        XCTAssertNil(measurer.occupied(.middle, at: 1))
        let result = measurer.occupied(.right, at: 2)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.forward ?? false)
        XCTAssertEqual(result?.kmh ?? 0, 156.6, accuracy: 0.01)
    }

    func testBackwardPassIsDetected() {
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 50, distanceMiddleRightCm: 50, scale: .h0)
        XCTAssertNil(measurer.occupied(.right, at: 0))
        XCTAssertNil(measurer.occupied(.middle, at: 1))
        let result = measurer.occupied(.left, at: 2)
        XCTAssertNotNil(result)
        XCTAssertFalse(result?.forward ?? true)
        XCTAssertEqual(result?.kmh ?? 0, 156.6, accuracy: 0.01)
    }

    func testDifferentSegmentLengthsAreAveraged() {
        // Abschnitt 1: 100 cm in 1 s -> 1 m/s; Abschnitt 2: 50 cm in 1 s -> 0,5 m/s; H0-Mittel aus beiden
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 100, distanceMiddleRightCm: 50, scale: .h0)
        _ = measurer.occupied(.left, at: 0)
        _ = measurer.occupied(.middle, at: 1)
        let result = measurer.occupied(.right, at: 2)
        let v1 = ModelScale.h0.scaleSpeed(distanceCm: 100, seconds: 1)!
        let v2 = ModelScale.h0.scaleSpeed(distanceCm: 50, seconds: 1)!
        XCTAssertEqual(result?.kmh ?? 0, (v1 + v2) / 2, accuracy: 0.01)
    }

    func testRepeatedTriggerOfSameSensorIsIgnored() {
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 50, distanceMiddleRightCm: 50, scale: .h0)
        XCTAssertNil(measurer.occupied(.left, at: 0))
        XCTAssertNil(measurer.occupied(.left, at: 0.1))
        XCTAssertNil(measurer.occupied(.middle, at: 1))
        let result = measurer.occupied(.right, at: 2)
        XCTAssertNotNil(result)
    }

    func testInvalidSequenceResetsWithoutResult() {
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 50, distanceMiddleRightCm: 50, scale: .h0)
        XCTAssertNil(measurer.occupied(.left, at: 0))
        XCTAssertNil(measurer.occupied(.right, at: 0.5))
        XCTAssertNil(measurer.occupied(.middle, at: 1))
        // nach drei widersprüchlichen Ereignissen wird zurückgesetzt, keine Messung
        XCTAssertNil(measurer.occupied(.left, at: 1.5))
    }

    func testSimultaneousTriggersAreRejected() {
        // Drei Melder im selben Augenblick (z.B. erste Rückmeldung der Z21): keine Fantasiegeschwindigkeit
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 50, distanceMiddleRightCm: 50, scale: .h0)
        XCTAssertNil(measurer.occupied(.left, at: 1))
        XCTAssertNil(measurer.occupied(.middle, at: 1.000001))
        XCTAssertNil(measurer.occupied(.right, at: 1.000002))
        // danach ist eine normale Durchfahrt wieder möglich
        XCTAssertNil(measurer.occupied(.left, at: 5))
        XCTAssertNil(measurer.occupied(.middle, at: 6))
        XCTAssertNotNil(measurer.occupied(.right, at: 7))
    }

    func testStaleSequenceTimesOut() {
        let measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: 50, distanceMiddleRightCm: 50, scale: .h0)
        measurer.timeoutSeconds = 5
        XCTAssertNil(measurer.occupied(.left, at: 0))
        XCTAssertNil(measurer.occupied(.middle, at: 10))
        // Sequenz war länger als timeoutSeconds unterbrochen: links/Mitte zählt nicht mehr, neuer Versuch
        XCTAssertNil(measurer.occupied(.right, at: 10.5))
    }
}
