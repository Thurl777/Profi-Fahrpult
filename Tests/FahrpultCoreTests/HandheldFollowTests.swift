import XCTest
@testable import FahrpultCore

final class HandheldFollowTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1000)

    func testLocoAlreadyOnThrottleChangesNothing() {
        let r = HandheldFollow.throttleToReplace(addresses: [3, 23], lastUse: [t0, t0], newAddress: 23)
        XCTAssertNil(r)
    }

    func testEmptyThrottleIsUsedFirst() {
        let r = HandheldFollow.throttleToReplace(addresses: [3, nil], lastUse: [t0, t0.addingTimeInterval(60)],
                                                 newAddress: 50)
        XCTAssertEqual(r, 1)
    }

    func testLeastRecentlyUsedThrottleIsReplaced() {
        // Regler 1 wurde gerade noch an der Multimaus gefahren, Regler 2 seit einer Minute nicht mehr
        let r = HandheldFollow.throttleToReplace(addresses: [3, 23],
                                                 lastUse: [t0.addingTimeInterval(60), t0],
                                                 newAddress: 50)
        XCTAssertEqual(r, 1)
        let r2 = HandheldFollow.throttleToReplace(addresses: [3, 23],
                                                  lastUse: [t0, t0.addingTimeInterval(60)],
                                                  newAddress: 50)
        XCTAssertEqual(r2, 0)
    }

    func testLockedThrottleIsNeverReplaced() {
        let r = HandheldFollow.throttleToReplace(addresses: [3, 23], lastUse: [t0, t0.addingTimeInterval(60)],
                                                 newAddress: 50, locked: [0])
        XCTAssertEqual(r, 1)
        let none = HandheldFollow.throttleToReplace(addresses: [3, 23], lastUse: [t0, t0],
                                                    newAddress: 50, locked: [0, 1])
        XCTAssertNil(none)
    }

    func testInvalidAddress() {
        XCTAssertNil(HandheldFollow.throttleToReplace(addresses: [nil, nil], lastUse: [t0, t0], newAddress: 0))
    }
}
