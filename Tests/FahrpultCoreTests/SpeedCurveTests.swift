import XCTest
@testable import FahrpultCore

final class SpeedCurveTests: XCTestCase {

    func testLinearWithoutMeasurements() {
        let curve = SpeedCurve(points: [], maxStep: 126, fallbackMaxKmh: 70)
        XCTAssertFalse(curve.hasMeasurements)
        XCTAssertEqual(curve.kmh(atStep: 0), 0)
        XCTAssertEqual(curve.kmh(atStep: 63), 35, accuracy: 0.001)
        XCTAssertEqual(curve.kmh(atStep: 126), 70, accuracy: 0.001)
        XCTAssertEqual(curve.scaleMax, 70)
    }

    func testInterpolationBetweenPoints() {
        let points = [SpeedPoint(step: 60, maxStep: 126, kmh: 42),
                      SpeedPoint(step: 10, maxStep: 126, kmh: 8),
                      SpeedPoint(step: 126, maxStep: 126, kmh: 70)]
        let curve = SpeedCurve(points: points, maxStep: 126, fallbackMaxKmh: 120)
        XCTAssertTrue(curve.hasMeasurements)
        XCTAssertEqual(curve.points.map { $0.kmh }, [8, 42, 70])
        XCTAssertEqual(curve.kmh(atStep: 5), 4, accuracy: 0.001)       // zwischen 0 und FS 10
        XCTAssertEqual(curve.kmh(atStep: 10), 8, accuracy: 0.001)
        XCTAssertEqual(curve.kmh(atStep: 35), 25, accuracy: 0.001)     // Mitte zwischen FS 10 und 60
        XCTAssertEqual(curve.kmh(atStep: 93), 56, accuracy: 0.001)     // Mitte zwischen FS 60 und 126
        XCTAssertEqual(curve.topSpeed, 70, accuracy: 0.001)
        XCTAssertEqual(curve.scaleMax, 70)
    }

    func testExtrapolationAboveLastPoint() {
        let points = [SpeedPoint(step: 40, maxStep: 126, kmh: 30), SpeedPoint(step: 80, maxStep: 126, kmh: 50)]
        let curve = SpeedCurve(points: points, maxStep: 126, fallbackMaxKmh: 120)
        // Steigung 20 km/h auf 40 FS -> bei FS 126 noch 23 km/h mehr
        XCTAssertEqual(curve.topSpeed, 73, accuracy: 0.001)
        XCTAssertEqual(curve.scaleMax, 80)

        let single = SpeedCurve(points: [SpeedPoint(step: 63, maxStep: 126, kmh: 40)], maxStep: 126, fallbackMaxKmh: 0)
        XCTAssertEqual(single.topSpeed, 80, accuracy: 0.001)

        // fallende Messung: oberhalb nicht kleiner als der letzte Punkt
        let falling = SpeedCurve(points: [SpeedPoint(step: 50, maxStep: 126, kmh: 60),
                                          SpeedPoint(step: 100, maxStep: 126, kmh: 55)],
                                 maxStep: 126, fallbackMaxKmh: 0)
        XCTAssertEqual(falling.topSpeed, 55, accuracy: 0.001)
    }

    func testPointsSurviveSpeedStepChange() {
        let p = SpeedPoint(step: 63, maxStep: 126, kmh: 40)
        XCTAssertEqual(p.step(maxStep: 28), 14)
        let curve28 = SpeedCurve(points: [p], maxStep: 28, fallbackMaxKmh: 0)
        XCTAssertEqual(curve28.kmh(atStep: 14), 40, accuracy: 0.001)
    }

    func testDuplicateStepsAndStepZero() {
        let curve = SpeedCurve(points: [SpeedPoint(step: 0, maxStep: 126, kmh: 5),
                                        SpeedPoint(step: 63, maxStep: 126, kmh: 30),
                                        SpeedPoint(step: 63, maxStep: 126, kmh: 40)],
                               maxStep: 126, fallbackMaxKmh: 0)
        XCTAssertEqual(curve.points.count, 1)
        XCTAssertEqual(curve.kmh(atStep: 0), 0)
        XCTAssertEqual(curve.kmh(atStep: 63), 40, accuracy: 0.001)
    }

    func testImplausiblePointsAreIgnored() {
        // Fehlmessung mit 150 Mio. km/h darf Tacho und Grafik nicht sprengen
        let curve = SpeedCurve(points: [SpeedPoint(step: 40, maxStep: 126, kmh: 1.5e8),
                                        SpeedPoint(step: 63, maxStep: 126, kmh: 40)],
                               maxStep: 126, fallbackMaxKmh: 0)
        XCTAssertEqual(curve.points.count, 1)
        XCTAssertEqual(curve.topSpeed, 80, accuracy: 0.001)

        // steile Extrapolation wird begrenzt
        let steep = SpeedCurve(points: [SpeedPoint(step: 1, maxStep: 126, kmh: 900)], maxStep: 126, fallbackMaxKmh: 0)
        XCTAssertEqual(steep.topSpeed, SpeedPoint.maxKmh, accuracy: 0.001)
        XCTAssertEqual(steep.scaleMax, 1000)
    }

    func testScaleSpeed() {
        // 1 m in 4,5 s in H0: 0,2222 m/s * 3,6 * 87 = 69,6 km/h
        XCTAssertEqual(ModelScale.h0.scaleSpeed(distanceCm: 100, seconds: 4.5) ?? 0, 69.6, accuracy: 0.01)
        XCTAssertEqual(ModelScale.n.scaleSpeed(distanceCm: 50, seconds: 5) ?? 0, 57.6, accuracy: 0.01)
        XCTAssertNil(ModelScale.h0.scaleSpeed(distanceCm: 100, seconds: 0))
        XCTAssertNil(ModelScale.h0.scaleSpeed(distanceCm: 0, seconds: 3))
    }
}
