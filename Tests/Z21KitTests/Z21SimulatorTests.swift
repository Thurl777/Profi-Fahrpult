import XCTest
@testable import Z21Kit

/// Integrationstest gegen tools/z21_simulator.py (oder eine echte Z21).
/// Wird nur ausgeführt, wenn die Umgebungsvariable Z21_HOST gesetzt ist, z.B.:
///   python3 tools/z21_simulator.py &
///   Z21_HOST=127.0.0.1 swift test
final class Z21SimulatorTests: XCTestCase, Z21ClientObserver {

    private var client: Z21Client!
    private var locoUpdates: [LocoInfo] = []

    private func wait(_ timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func z21Client(_ client: Z21Client, locoChanged info: LocoInfo) {
        locoUpdates.append(info)
    }

    func testRoundTripWithSimulator() throws {
        guard let host = ProcessInfo.processInfo.environment["Z21_HOST"] else {
            throw XCTSkip("Z21_HOST nicht gesetzt")
        }
        client = Z21Client()
        client.addObserver(self)
        client.connect(host: host)
        XCTAssertTrue(wait(5) { client.connectionState == .connected })
        XCTAssertTrue(wait(3) { client.serialNumber != nil && client.firmware != nil })
        XCTAssertTrue(wait(3) { client.systemState != nil })

        client.setTrackPower(true)
        XCTAssertTrue(wait(3) { client.trackStatus == .on })

        client.subscribeLoco(1234)
        client.setLocoDrive(address: 1234, speedSteps: .steps28, step: 17, forward: false)
        client.setLocoFunction(address: 1234, function: 3, on: true)
        locoUpdates.removeAll()
        XCTAssertTrue(wait(3) { locoUpdates.contains { $0.address == 1234 && $0.isFunctionOn(3) } })
        let info = client.locoInfo(1234)
        XCTAssertEqual(info?.step, 17)
        XCTAssertEqual(info?.forward, false)
        XCTAssertEqual(info?.speedSteps, .steps28)

        client.setTurnout(address: 12, output: 1)
        client.requestTurnoutInfo(12)
        XCTAssertTrue(wait(3) { client.turnouts[12] == .output2 })

        var cvResult: CVResult?
        client.writeCV(8, value: 8) { cvResult = $0 }
        XCTAssertTrue(wait(5) { cvResult != nil })
        XCTAssertEqual(cvResult, .value(8))
        cvResult = nil
        client.readCV(1) { cvResult = $0 }
        XCTAssertTrue(wait(5) { cvResult != nil })
        XCTAssertEqual(cvResult, .value(3))
        cvResult = nil
        client.readCV(999) { cvResult = $0 }
        XCTAssertTrue(wait(5) { cvResult != nil })
        XCTAssertEqual(cvResult, .noAcknowledge)

        client.leaveProgrammingMode()
        XCTAssertTrue(wait(3) { client.trackStatus == .on })
        client.emergencyStopAll()
        XCTAssertTrue(wait(3) { client.trackStatus == .emergencyStop })
        client.disconnect()
        XCTAssertEqual(client.connectionState, .disconnected)
    }
}
