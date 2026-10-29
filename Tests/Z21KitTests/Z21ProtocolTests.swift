import XCTest
@testable import Z21Kit

final class Z21ProtocolTests: XCTestCase {

    private func hex(_ data: Data) -> String {
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    // Beispiele aus der Z21-LAN-Protokollspezifikation
    func testSystemCommands() {
        XCTAssertEqual(hex(Z21Codec.getSerialNumber()), "04 00 10 00")
        XCTAssertEqual(hex(Z21Codec.getHardwareInfo()), "04 00 1A 00")
        XCTAssertEqual(hex(Z21Codec.logoff()), "04 00 30 00")
        XCTAssertEqual(hex(Z21Codec.systemStateGetData()), "04 00 85 00")
        XCTAssertEqual(hex(Z21Codec.getXBusVersion()), "07 00 40 00 21 21 00")
        XCTAssertEqual(hex(Z21Codec.getStatus()), "07 00 40 00 21 24 05")
        XCTAssertEqual(hex(Z21Codec.setTrackPowerOff()), "07 00 40 00 21 80 A1")
        XCTAssertEqual(hex(Z21Codec.setTrackPowerOn()), "07 00 40 00 21 81 A0")
        XCTAssertEqual(hex(Z21Codec.setStop()), "06 00 40 00 80 80")
        XCTAssertEqual(hex(Z21Codec.getFirmwareVersion()), "07 00 40 00 F1 0A FB")
        XCTAssertEqual(hex(Z21Codec.setBroadcastFlags([.drivingAndSwitching, .systemState])), "08 00 50 00 01 01 00 00")
    }

    func testLocoCommands() {
        XCTAssertEqual(hex(Z21Codec.getLocoInfo(address: 3)), "09 00 40 00 E3 F0 00 03 10")
        // Lange Adresse: obere zwei Bits im MSB gesetzt
        XCTAssertEqual(hex(Z21Codec.getLocoInfo(address: 1000)), "09 00 40 00 E3 F0 C3 E8 38")
        XCTAssertEqual(hex(Z21Codec.setLocoDrive(address: 3, speedSteps: .steps128, step: 1, forward: true)),
                       "0A 00 40 00 E4 13 00 03 82 76")
        XCTAssertEqual(hex(Z21Codec.setLocoFunction(address: 3, function: 0, action: .on)),
                       "0A 00 40 00 E4 F8 00 03 40 5F")
        XCTAssertEqual(hex(Z21Codec.setLocoFunction(address: 3, function: 28, action: .toggle)),
                       "0A 00 40 00 E4 F8 00 03 9C 83")
        XCTAssertEqual(hex(Z21Codec.setLocoEmergencyStop(address: 3)), "08 00 40 00 92 00 03 91")
    }

    func testSpeedEncoding28() {
        let s = SpeedSteps.steps28
        XCTAssertEqual(s.encode(step: 0, forward: true), 0x80)
        XCTAssertEqual(s.encode(step: 1, forward: true), 0x82)
        XCTAssertEqual(s.encode(step: 2, forward: true), 0x92)
        XCTAssertEqual(s.encode(step: 3, forward: false), 0x03)
        XCTAssertEqual(s.encode(step: 28, forward: true), 0x9F)
        XCTAssertEqual(s.encode(step: 0, forward: true, emergencyStop: true), 0x81)
        for step in 0...28 {
            for fwd in [true, false] {
                let d = s.decode(s.encode(step: step, forward: fwd))
                XCTAssertEqual(d.step, step)
                XCTAssertEqual(d.forward, fwd)
                XCTAssertFalse(d.emergencyStop)
            }
        }
        XCTAssertTrue(s.decode(0x81).emergencyStop)
        XCTAssertTrue(s.decode(0x91).emergencyStop)
    }

    func testSpeedEncodingRoundTrip() {
        for steps in [SpeedSteps.steps14, .steps128] {
            for step in 0...steps.maxStep {
                let d = steps.decode(steps.encode(step: step, forward: true))
                XCTAssertEqual(d.step, step)
                XCTAssertTrue(d.forward)
            }
        }
        XCTAssertEqual(SpeedSteps.steps128.encode(step: 126, forward: true), 0xFF)
        XCTAssertEqual(SpeedSteps.steps14.encode(step: 14, forward: false), 0x0F)
    }

    func testTurnoutCommands() {
        XCTAssertEqual(hex(Z21Codec.setTurnout(address: 1, output: 1, activate: true)), "09 00 40 00 53 00 00 89 DA")
        XCTAssertEqual(hex(Z21Codec.setTurnout(address: 1, output: 0, activate: false)), "09 00 40 00 53 00 00 80 D3")
        XCTAssertEqual(hex(Z21Codec.getTurnoutInfo(address: 5)), "08 00 40 00 43 00 04 47")
    }

    func testProgrammingCommands() {
        XCTAssertEqual(hex(Z21Codec.cvRead(cv: 1)), "09 00 40 00 23 11 00 00 32")
        XCTAssertEqual(hex(Z21Codec.cvWrite(cv: 29, value: 6)), "0A 00 40 00 24 12 00 1C 06 2C")
        XCTAssertEqual(hex(Z21Codec.pomWriteByte(address: 3, cv: 1, value: 5)), "0C 00 40 00 E6 30 00 03 EC 00 05 3C")
    }

    func testParseLocoInfo() {
        // Lok 3, 128 FS, vorwärts Fahrstufe 10, F0 + F2 + F5 + F13 an
        let bytes: [UInt8] = [0x0E, 0x00, 0x40, 0x00, 0xEF, 0x00, 0x03, 0x04, 0x8B, 0x12, 0x01, 0x01, 0x00]
        var withXor = bytes
        withXor.append(Z21Codec.xor(Array(bytes[4...])))
        withXor[0] = UInt8(withXor.count)
        let msgs = Z21Codec.parse(Data(withXor))
        XCTAssertEqual(msgs.count, 1)
        guard case .locoInfo(let info)? = msgs.first else { return XCTFail("keine Lok-Info") }
        XCTAssertEqual(info.address, 3)
        XCTAssertEqual(info.speedSteps, .steps128)
        XCTAssertEqual(info.step, 10)
        XCTAssertTrue(info.forward)
        XCTAssertTrue(info.isFunctionOn(0))
        XCTAssertTrue(info.isFunctionOn(2))
        XCTAssertFalse(info.isFunctionOn(1))
        XCTAssertTrue(info.isFunctionOn(5))
        XCTAssertTrue(info.isFunctionOn(13))
        XCTAssertFalse(info.isFunctionOn(21))
    }

    func testParseMultiplePacketsAndChecksum() {
        var data = Data([0x07, 0x00, 0x40, 0x00, 0x61, 0x01, 0x60])          // Gleisspannung an
        data.append(contentsOf: [0x07, 0x00, 0x40, 0x00, 0x61, 0x00, 0x60])   // falsche Prüfsumme
        data.append(contentsOf: [0x08, 0x00, 0x10, 0x00, 0x39, 0x30, 0x00, 0x00]) // Seriennummer 12345
        let msgs = Z21Codec.parse(data)
        XCTAssertEqual(msgs, [.trackPowerOn, .serialNumber(12345)])
    }

    func testParseSystemState() {
        let p: [UInt8] = [0x14, 0x00, 0x84, 0x00,
                          0xF4, 0x01,  // 500 mA
                          0x00, 0x00,
                          0xE8, 0x01,  // 488 mA
                          0x23, 0x00,  // 35 °C
                          0x30, 0x4B,  // 19248 mV
                          0x38, 0x4A,  // 18999 mV
                          0x02, 0x00, 0x00, 0x00]
        guard case .systemState(let s)? = Z21Codec.parse(Data(p)).first else { return XCTFail() }
        XCTAssertEqual(s.mainCurrent, 500)
        XCTAssertEqual(s.filteredMainCurrent, 488)
        XCTAssertEqual(s.temperature, 35)
        XCTAssertEqual(s.supplyVoltage, 19248)
        XCTAssertTrue(s.centralState.contains(.trackVoltageOff))
        XCTAssertEqual(Z21Client.trackStatus(from: s.centralState), .off)
    }

    func testParseCVAndTurnout() {
        XCTAssertEqual(Z21Codec.parse(Data([0x0A, 0x00, 0x40, 0x00, 0x64, 0x14, 0x00, 0x00, 0x03, 0x73])),
                       [.cvResult(cv: 1, value: 3)])
        XCTAssertEqual(Z21Codec.parse(Data([0x07, 0x00, 0x40, 0x00, 0x61, 0x13, 0x72])), [.cvNack])
        XCTAssertEqual(Z21Codec.parse(Data([0x09, 0x00, 0x40, 0x00, 0x43, 0x00, 0x04, 0x02, 0x45])),
                       [.turnoutInfo(address: 5, position: .output2)])
        XCTAssertEqual(Z21Codec.firmwareString(0x143), "1.43")
    }
}
