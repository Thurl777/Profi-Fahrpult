import XCTest
@testable import Z21Kit

/// Erkennung von Bedienung „von außen“ (Multimaus, andere App) ohne Netzwerk
final class Z21ClientTests: XCTestCase, Z21ClientObserver {

    private var client: Z21Client!
    private var clock = Date(timeIntervalSince1970: 1000)
    private var external: [LocoInfo] = []

    override func setUp() {
        super.setUp()
        client = Z21Client()
        client.now = { [unowned self] in self.clock }
        client.addObserver(self)
        external = []
    }

    func z21Client(_ client: Z21Client, externalLocoActivity info: LocoInfo) {
        external.append(info)
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    func testBroadcastFlags() {
        XCTAssertFalse(client.broadcastFlags.contains(.allLocoInfo))
        client.receiveAllLocoInfo = true
        XCTAssertTrue(client.broadcastFlags.contains(.allLocoInfo))
        XCTAssertTrue(client.broadcastFlags.contains(.drivingAndSwitching))
        XCTAssertEqual(Z21.BroadcastFlags.allLocoInfo.rawValue, 0x0001_0000)
    }

    func testEchoOfOwnCommandIsNotExternal() {
        client.setLocoDrive(address: 3, speedSteps: .steps128, step: 20, forward: true)
        client.handle(.locoInfo(LocoInfo(address: 3, step: 20)))
        // Zentrale meldet einen leicht anderen Wert kurz nach dem eigenen Befehl
        advance(0.3)
        client.handle(.locoInfo(LocoInfo(address: 3, step: 21)))
        XCTAssertTrue(external.isEmpty)
    }

    func testChangeFromHandheldIsExternal() {
        client.subscribeLoco(3)
        client.handle(.locoInfo(LocoInfo(address: 3, step: 0)))
        advance(5)
        client.handle(.locoInfo(LocoInfo(address: 3, step: 10)))
        XCTAssertEqual(external.map { $0.address }, [3])
        XCTAssertEqual(client.lastExternalActivity[3], clock)

        // gleiche Info noch einmal: keine neue Bedienung
        advance(1)
        client.handle(.locoInfo(LocoInfo(address: 3, step: 10)))
        XCTAssertEqual(external.count, 1)

        // Funktion an der Multimaus geschaltet
        var info = LocoInfo(address: 3, step: 10)
        info.setFunction(0, on: true)
        client.handle(.locoInfo(info))
        XCTAssertEqual(external.count, 2)
    }

    func testUnknownLocoCountsOnlyWhenActive() {
        advance(5)
        client.handle(.locoInfo(LocoInfo(address: 50)))
        XCTAssertTrue(external.isEmpty)
        client.handle(.locoInfo(LocoInfo(address: 51, step: 5)))
        XCTAssertEqual(external.map { $0.address }, [51])
    }

    func testNoExternalActivityRightAfterEmergencyStop() {
        client.handle(.emergencyStopped)
        advance(0.5)
        client.handle(.locoInfo(LocoInfo(address: 7, step: 0, emergencyStop: true, functions: 1)))
        XCTAssertTrue(external.isEmpty)
        advance(3)
        client.handle(.locoInfo(LocoInfo(address: 7, step: 12, functions: 1)))
        XCTAssertEqual(external.map { $0.address }, [7])
    }
}
