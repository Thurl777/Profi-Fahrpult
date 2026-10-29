import Foundation

// Implementierung des öffentlich dokumentierten "Z21 LAN Protokoll" von Roco/Fleischmann.
// Alle Pakete: DataLen (UInt16 LE) | Header (UInt16 LE) | Data
// X-Bus-Pakete (Header 0x40) enden mit einer XOR-Prüfsumme über X-Header und Daten.

public enum Z21 {
    public static let defaultHost = "192.168.0.111"
    public static let defaultPort: UInt16 = 21105

    public enum Header: UInt16 {
        case getSerialNumber = 0x10
        case getCode = 0x18
        case getHardwareInfo = 0x1A
        case logoff = 0x30
        case xbus = 0x40
        case setBroadcastFlags = 0x50
        case getBroadcastFlags = 0x51
        case getLocoMode = 0x60
        case setLocoMode = 0x61
        case getTurnoutMode = 0x70
        case setTurnoutMode = 0x71
        case rmBusDataChanged = 0x80
        case rmBusGetData = 0x81
        case rmBusProgramModule = 0x82
        case systemStateDataChanged = 0x84
        case systemStateGetData = 0x85
        case railComDataChanged = 0x88
        case railComGetData = 0x89
    }

    /// Broadcast-Flags für LAN_SET_BROADCASTFLAGS
    public struct BroadcastFlags: OptionSet {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        /// Fahren & Schalten (Lok-Infos abonnierter Loks, Weichen-Infos, Gleisstatus)
        public static let drivingAndSwitching = BroadcastFlags(rawValue: 0x0000_0001)
        /// Rückmelder am R-Bus
        public static let rmBus = BroadcastFlags(rawValue: 0x0000_0002)
        /// RailCom-Daten abonnierter Loks
        public static let railComSubscribed = BroadcastFlags(rawValue: 0x0000_0004)
        /// Systemzustand (Ströme, Spannung, Temperatur)
        public static let systemState = BroadcastFlags(rawValue: 0x0000_0100)
    }

    /// Bits von CentralState aus LAN_SYSTEMSTATE_DATACHANGED bzw. LAN_X_STATUS_CHANGED
    public struct CentralState: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let emergencyStop = CentralState(rawValue: 0x01)
        public static let trackVoltageOff = CentralState(rawValue: 0x02)
        public static let shortCircuit = CentralState(rawValue: 0x04)
        public static let programmingModeActive = CentralState(rawValue: 0x20)
    }

    public struct CentralStateEx: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let highTemperature = CentralStateEx(rawValue: 0x01)
        public static let powerLost = CentralStateEx(rawValue: 0x02)
        public static let shortCircuitExternal = CentralStateEx(rawValue: 0x04)
        public static let shortCircuitInternal = CentralStateEx(rawValue: 0x08)
    }
}

// MARK: - Fahrstufen

public enum SpeedSteps: Int, Codable {
    case steps14 = 14
    case steps28 = 28
    case steps128 = 128

    /// Höchste nutzbare Fahrstufe (bei 128 FS sind 126 Stufen fahrbar)
    public var maxStep: Int {
        switch self {
        case .steps14: return 14
        case .steps28: return 28
        case .steps128: return 126
        }
    }

    /// Kennung für LAN_X_SET_LOCO_DRIVE (0x10 / 0x12 / 0x13)
    var driveCommand: UInt8 {
        switch self {
        case .steps14: return 0x10
        case .steps28: return 0x12
        case .steps128: return 0x13
        }
    }

    /// Kennung KKK aus DB2 von LAN_X_LOCO_INFO
    init(locoInfoCode: UInt8) {
        switch locoInfoCode & 0x07 {
        case 0: self = .steps14
        case 2: self = .steps28
        default: self = .steps128
        }
    }

    public var title: String { return "\(rawValue) FS" }

    /// Kodiert Fahrstufe + Richtung in das Byte RVVVVVVV.
    public func encode(step: Int, forward: Bool, emergencyStop: Bool = false) -> UInt8 {
        let dir: UInt8 = forward ? 0x80 : 0x00
        let s = max(0, min(step, maxStep))
        switch self {
        case .steps128:
            if emergencyStop { return dir | 0x01 }
            return dir | (s == 0 ? 0 : UInt8(s + 1))
        case .steps14:
            if emergencyStop { return dir | 0x01 }
            return dir | (s == 0 ? 0 : UInt8(s + 1))
        case .steps28:
            // 5-Bit-Wert: 0/1 = Halt, 2/3 = Nothalt, 4...31 = Fahrstufe 1...28
            // Bit 4 des Bytes enthält das niederwertigste Bit (DCC "C"-Bit).
            let v: Int
            if emergencyStop { v = 2 } else { v = s == 0 ? 0 : s + 3 }
            let byte = UInt8(((v & 0x01) << 4) | ((v >> 1) & 0x0F))
            return dir | byte
        }
    }

    /// Dekodiert das Byte RVVVVVVV in (Fahrstufe, vorwärts, Nothalt).
    public func decode(_ byte: UInt8) -> (step: Int, forward: Bool, emergencyStop: Bool) {
        let forward = byte & 0x80 != 0
        switch self {
        case .steps128:
            let v = Int(byte & 0x7F)
            if v == 1 { return (0, forward, true) }
            return (v == 0 ? 0 : v - 1, forward, false)
        case .steps14:
            let v = Int(byte & 0x0F)
            if v == 1 { return (0, forward, true) }
            return (v == 0 ? 0 : v - 1, forward, false)
        case .steps28:
            let v = (Int(byte & 0x0F) << 1) | Int((byte >> 4) & 0x01)
            if v <= 1 { return (0, forward, false) }
            if v <= 3 { return (0, forward, true) }
            return (v - 3, forward, false)
        }
    }
}

// MARK: - Datenstrukturen der Antworten

public struct LocoInfo: Equatable {
    public var address: UInt16
    public var speedSteps: SpeedSteps
    public var step: Int
    public var forward: Bool
    public var emergencyStop: Bool
    /// Lok wird von einem anderen X-Bus-Gerät gesteuert
    public var busy: Bool
    public var doubleTraction: Bool
    public var smartSearch: Bool
    /// Bit n = Funktion Fn (F0 ... F31)
    public var functions: UInt32

    public init(address: UInt16, speedSteps: SpeedSteps = .steps128, step: Int = 0, forward: Bool = true,
                emergencyStop: Bool = false, busy: Bool = false, doubleTraction: Bool = false,
                smartSearch: Bool = false, functions: UInt32 = 0) {
        self.address = address
        self.speedSteps = speedSteps
        self.step = step
        self.forward = forward
        self.emergencyStop = emergencyStop
        self.busy = busy
        self.doubleTraction = doubleTraction
        self.smartSearch = smartSearch
        self.functions = functions
    }

    public func isFunctionOn(_ index: Int) -> Bool {
        guard index >= 0 && index < 32 else { return false }
        return functions & (UInt32(1) << UInt32(index)) != 0
    }

    public mutating func setFunction(_ index: Int, on: Bool) {
        guard index >= 0 && index < 32 else { return }
        let mask = UInt32(1) << UInt32(index)
        if on { functions |= mask } else { functions &= ~mask }
    }
}

public struct SystemState: Equatable {
    public var mainCurrent: Int          // mA
    public var progCurrent: Int          // mA
    public var filteredMainCurrent: Int  // mA
    public var temperature: Int          // °C
    public var supplyVoltage: Int        // mV
    public var vccVoltage: Int           // mV (Gleisspannung)
    public var centralState: Z21.CentralState
    public var centralStateEx: Z21.CentralStateEx

    public init(mainCurrent: Int = 0, progCurrent: Int = 0, filteredMainCurrent: Int = 0, temperature: Int = 0,
                supplyVoltage: Int = 0, vccVoltage: Int = 0,
                centralState: Z21.CentralState = [], centralStateEx: Z21.CentralStateEx = []) {
        self.mainCurrent = mainCurrent
        self.progCurrent = progCurrent
        self.filteredMainCurrent = filteredMainCurrent
        self.temperature = temperature
        self.supplyVoltage = supplyVoltage
        self.vccVoltage = vccVoltage
        self.centralState = centralState
        self.centralStateEx = centralStateEx
    }
}

public struct RailComData: Equatable {
    public var address: UInt16
    public var receiveCounter: UInt32
    public var errorCounter: UInt16
    public var options: UInt8
    public var speed: Int
    public var qos: Int
}

/// Zustand eines Weichenausgangs aus LAN_X_TURNOUT_INFO
public enum TurnoutPosition: UInt8 {
    case unknown = 0      // noch nicht geschaltet
    case output1 = 1      // P = 0 (z.B. abzweigend / rot)
    case output2 = 2      // P = 1 (z.B. gerade / grün)
    case invalid = 3
}

// MARK: - Eingehende Nachrichten

public enum Z21Message: Equatable {
    case serialNumber(UInt32)
    case hardwareInfo(hardwareType: UInt32, firmware: UInt32)
    case code(UInt8)
    case broadcastFlags(UInt32)
    case locoMode(address: UInt16, mode: UInt8)
    case turnoutMode(address: UInt16, mode: UInt8)

    case trackPowerOff
    case trackPowerOn
    case programmingMode
    case trackShortCircuit
    case unknownCommand
    case statusChanged(Z21.CentralState)
    case emergencyStopped
    case xbusVersion(version: UInt8, commandStationID: UInt8)
    case firmwareVersion(major: Int, minor: Int)

    case locoInfo(LocoInfo)
    /// Adresse ist 1-basiert, wie sie in der App angezeigt wird
    case turnoutInfo(address: UInt16, position: TurnoutPosition)

    /// CV-Nummer 1-basiert
    case cvResult(cv: UInt16, value: UInt8)
    case cvNack
    case cvNackShortCircuit

    case systemState(SystemState)
    case rmBus(group: UInt8, data: [UInt8])
    case railCom(RailComData)

    case unknown(header: UInt16, payload: [UInt8])
}

// MARK: - Codec

public enum Z21Codec {

    // MARK: Hilfsfunktionen

    static func packet(header: Z21.Header, payload: [UInt8] = []) -> Data {
        let len = UInt16(4 + payload.count)
        var bytes: [UInt8] = [UInt8(len & 0xFF), UInt8(len >> 8),
                              UInt8(header.rawValue & 0xFF), UInt8(header.rawValue >> 8)]
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    /// X-Bus-Paket: hängt automatisch die XOR-Prüfsumme an.
    static func xbus(_ bytes: [UInt8]) -> Data {
        var payload = bytes
        payload.append(xor(bytes))
        return packet(header: .xbus, payload: payload)
    }

    static func xor(_ bytes: [UInt8]) -> UInt8 {
        return bytes.reduce(0) { $0 ^ $1 }
    }

    /// Lokadresse -> (Adr_MSB, Adr_LSB). Ab Adresse 128 werden die beiden oberen Bits gesetzt.
    static func locoAddressBytes(_ address: UInt16) -> (UInt8, UInt8) {
        var msb = UInt8((address >> 8) & 0x3F)
        if address >= 128 { msb |= 0xC0 }
        return (msb, UInt8(address & 0xFF))
    }

    static func decodeLocoAddress(_ msb: UInt8, _ lsb: UInt8) -> UInt16 {
        return (UInt16(msb & 0x3F) << 8) | UInt16(lsb)
    }

    // MARK: Systembefehle

    public static func getSerialNumber() -> Data { return packet(header: .getSerialNumber) }
    public static func getHardwareInfo() -> Data { return packet(header: .getHardwareInfo) }
    public static func getCode() -> Data { return packet(header: .getCode) }
    public static func logoff() -> Data { return packet(header: .logoff) }
    public static func getBroadcastFlags() -> Data { return packet(header: .getBroadcastFlags) }
    public static func systemStateGetData() -> Data { return packet(header: .systemStateGetData) }

    public static func setBroadcastFlags(_ flags: Z21.BroadcastFlags) -> Data {
        let f = flags.rawValue
        return packet(header: .setBroadcastFlags,
                      payload: [UInt8(f & 0xFF), UInt8((f >> 8) & 0xFF), UInt8((f >> 16) & 0xFF), UInt8((f >> 24) & 0xFF)])
    }

    public static func getXBusVersion() -> Data { return xbus([0x21, 0x21]) }
    public static func getStatus() -> Data { return xbus([0x21, 0x24]) }
    public static func getFirmwareVersion() -> Data { return xbus([0xF1, 0x0A]) }
    public static func setTrackPowerOff() -> Data { return xbus([0x21, 0x80]) }
    public static func setTrackPowerOn() -> Data { return xbus([0x21, 0x81]) }
    /// Nothalt: alle Loks halten an, Gleisspannung bleibt eingeschaltet.
    public static func setStop() -> Data { return xbus([0x80]) }

    // MARK: Fahren

    public static func getLocoInfo(address: UInt16) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        return xbus([0xE3, 0xF0, msb, lsb])
    }

    public static func setLocoDrive(address: UInt16, speedSteps: SpeedSteps, step: Int, forward: Bool) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        let speed = speedSteps.encode(step: step, forward: forward)
        return xbus([0xE4, speedSteps.driveCommand, msb, lsb, speed])
    }

    /// Nothalt für eine einzelne Lok
    public static func setLocoEmergencyStop(address: UInt16) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        return xbus([0x92, msb, lsb])
    }

    public enum FunctionAction: UInt8 {
        case off = 0x00
        case on = 0x40
        case toggle = 0x80
    }

    public static func setLocoFunction(address: UInt16, function: Int, action: FunctionAction) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        let fn = UInt8(max(0, min(function, 31)))
        return xbus([0xE4, 0xF8, msb, lsb, action.rawValue | fn])
    }

    public static func purgeLoco(address: UInt16) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        return xbus([0xE3, 0x44, msb, lsb])
    }

    public static func getLocoMode(address: UInt16) -> Data {
        return packet(header: .getLocoMode, payload: [UInt8(address >> 8), UInt8(address & 0xFF)])
    }

    // MARK: Schalten

    /// - Parameter address: Weichenadresse 1-basiert (wie im Stellpult angezeigt)
    public static func getTurnoutInfo(address: UInt16) -> Data {
        let fadr = address &- 1
        return xbus([0x43, UInt8(fadr >> 8), UInt8(fadr & 0xFF)])
    }

    /// - Parameters:
    ///   - address: Weichenadresse 1-basiert
    ///   - output: 0 = Ausgang 1, 1 = Ausgang 2
    ///   - activate: Ausgang einschalten (true) bzw. wieder ausschalten (false)
    ///   - queue: Befehl in Warteschlange der Zentrale einreihen (ab FW 1.24)
    public static func setTurnout(address: UInt16, output: Int, activate: Bool, queue: Bool = false) -> Data {
        let fadr = address &- 1
        var db: UInt8 = 0x80
        if queue { db |= 0x20 }
        if activate { db |= 0x08 }
        if output != 0 { db |= 0x01 }
        return xbus([0x53, UInt8(fadr >> 8), UInt8(fadr & 0xFF), db])
    }

    // MARK: Programmieren

    /// CV lesen auf dem Programmiergleis (cv 1-basiert)
    public static func cvRead(cv: UInt16) -> Data {
        let a = cv &- 1
        return xbus([0x23, 0x11, UInt8((a >> 8) & 0x03), UInt8(a & 0xFF)])
    }

    /// CV schreiben auf dem Programmiergleis (cv 1-basiert)
    public static func cvWrite(cv: UInt16, value: UInt8) -> Data {
        let a = cv &- 1
        return xbus([0x24, 0x12, UInt8((a >> 8) & 0x03), UInt8(a & 0xFF), value])
    }

    /// CV schreiben auf dem Hauptgleis (POM)
    public static func pomWriteByte(address: UInt16, cv: UInt16, value: UInt8) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        let a = cv &- 1
        return xbus([0xE6, 0x30, msb, lsb, 0xEC | UInt8((a >> 8) & 0x03), UInt8(a & 0xFF), value])
    }

    /// CV lesen auf dem Hauptgleis (POM, benötigt RailCom-fähigen Decoder)
    public static func pomReadByte(address: UInt16, cv: UInt16) -> Data {
        let (msb, lsb) = locoAddressBytes(address)
        let a = cv &- 1
        return xbus([0xE6, 0x30, msb, lsb, 0xE4 | UInt8((a >> 8) & 0x03), UInt8(a & 0xFF), 0x00])
    }

    // MARK: Rückmelder / RailCom

    /// group 0 = Module 1-10, group 1 = Module 11-20
    public static func rmBusGetData(group: UInt8) -> Data {
        return packet(header: .rmBusGetData, payload: [group])
    }

    public static func railComGetData(address: UInt16) -> Data {
        return packet(header: .railComGetData, payload: [0x01, UInt8(address & 0xFF), UInt8(address >> 8)])
    }

    // MARK: - Parser

    /// Zerlegt ein UDP-Datagramm (kann mehrere Z21-Pakete enthalten) in Nachrichten.
    public static func parse(_ data: Data) -> [Z21Message] {
        let bytes = [UInt8](data)
        var result: [Z21Message] = []
        var offset = 0
        while offset + 4 <= bytes.count {
            let len = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            if len < 4 || offset + len > bytes.count { break }
            let header = UInt16(bytes[offset + 2]) | (UInt16(bytes[offset + 3]) << 8)
            let payload = Array(bytes[(offset + 4)..<(offset + len)])
            if let msg = parsePacket(header: header, payload: payload) {
                result.append(msg)
            }
            offset += len
        }
        return result
    }

    static func le16(_ p: [UInt8], _ i: Int) -> UInt16 {
        return UInt16(p[i]) | (UInt16(p[i + 1]) << 8)
    }

    static func le32(_ p: [UInt8], _ i: Int) -> UInt32 {
        return UInt32(p[i]) | (UInt32(p[i + 1]) << 8) | (UInt32(p[i + 2]) << 16) | (UInt32(p[i + 3]) << 24)
    }

    static func signed16(_ p: [UInt8], _ i: Int) -> Int {
        return Int(Int16(bitPattern: le16(p, i)))
    }

    static func parsePacket(header: UInt16, payload p: [UInt8]) -> Z21Message? {
        guard let h = Z21.Header(rawValue: header) else {
            return .unknown(header: header, payload: p)
        }
        switch h {
        case .getSerialNumber where p.count >= 4:
            return .serialNumber(le32(p, 0))
        case .getHardwareInfo where p.count >= 8:
            return .hardwareInfo(hardwareType: le32(p, 0), firmware: le32(p, 4))
        case .getCode where p.count >= 1:
            return .code(p[0])
        case .getBroadcastFlags where p.count >= 4:
            return .broadcastFlags(le32(p, 0))
        case .getLocoMode where p.count >= 3:
            return .locoMode(address: (UInt16(p[0]) << 8) | UInt16(p[1]), mode: p[2])
        case .getTurnoutMode where p.count >= 3:
            return .turnoutMode(address: (UInt16(p[0]) << 8) | UInt16(p[1]), mode: p[2])
        case .xbus:
            return parseXBus(p)
        case .systemStateDataChanged where p.count >= 14:
            let state = SystemState(mainCurrent: signed16(p, 0),
                                    progCurrent: signed16(p, 2),
                                    filteredMainCurrent: signed16(p, 4),
                                    temperature: signed16(p, 6),
                                    supplyVoltage: Int(le16(p, 8)),
                                    vccVoltage: Int(le16(p, 10)),
                                    centralState: Z21.CentralState(rawValue: p[12]),
                                    centralStateEx: Z21.CentralStateEx(rawValue: p[13]))
            return .systemState(state)
        case .rmBusDataChanged where p.count >= 11:
            return .rmBus(group: p[0], data: Array(p[1..<11]))
        case .railComDataChanged where p.count >= 13:
            let rc = RailComData(address: le16(p, 0),
                                 receiveCounter: le32(p, 2),
                                 errorCounter: le16(p, 6),
                                 options: p[9],
                                 speed: Int(p[10]),
                                 qos: Int(p[11]))
            return .railCom(rc)
        default:
            return .unknown(header: header, payload: p)
        }
    }

    static func parseXBus(_ p: [UInt8]) -> Z21Message? {
        guard p.count >= 2 else { return nil }
        // Prüfsumme: XOR über alle Bytes inkl. Prüfsumme muss 0 ergeben
        guard xor(p) == 0 else { return nil }
        let x = p[0]
        let db = Array(p[1..<(p.count - 1)])

        switch x {
        case 0x61 where db.count >= 1:
            switch db[0] {
            case 0x00: return .trackPowerOff
            case 0x01: return .trackPowerOn
            case 0x02: return .programmingMode
            case 0x08: return .trackShortCircuit
            case 0x12: return .cvNackShortCircuit
            case 0x13: return .cvNack
            case 0x82: return .unknownCommand
            default: break
            }
        case 0x62 where db.count >= 2 && db[0] == 0x22:
            return .statusChanged(Z21.CentralState(rawValue: db[1]))
        case 0x63 where db.count >= 3 && db[0] == 0x21:
            return .xbusVersion(version: db[1], commandStationID: db[2])
        case 0x64 where db.count >= 4 && db[0] == 0x14:
            let cv = ((UInt16(db[1]) << 8) | UInt16(db[2])) + 1
            return .cvResult(cv: cv, value: db[3])
        case 0x81 where db.count >= 1 && db[0] == 0x00:
            return .emergencyStopped
        case 0xF3 where db.count >= 3 && db[0] == 0x0A:
            return .firmwareVersion(major: bcd(db[1]), minor: bcd(db[2]))
        case 0x43 where db.count >= 3:
            let fadr = (UInt16(db[0]) << 8) | UInt16(db[1])
            return .turnoutInfo(address: fadr + 1, position: TurnoutPosition(rawValue: db[2] & 0x03) ?? .invalid)
        case 0xEF where db.count >= 6:
            let address = decodeLocoAddress(db[0], db[1])
            let steps = SpeedSteps(locoInfoCode: db[2])
            let busy = db[2] & 0x08 != 0
            let speed = steps.decode(db[3])
            let db4 = db[4]
            var functions: UInt32 = 0
            if db4 & 0x10 != 0 { functions |= 1 }                     // F0
            functions |= UInt32(db4 & 0x0F) << 1                       // F1-F4
            functions |= UInt32(db[5]) << 5                            // F5-F12
            if db.count >= 7 { functions |= UInt32(db[6]) << 13 }      // F13-F20
            if db.count >= 8 { functions |= UInt32(db[7]) << 21 }      // F21-F28
            if db.count >= 9 { functions |= UInt32(db[8] & 0x07) << 29 } // F29-F31
            let info = LocoInfo(address: address,
                                speedSteps: steps,
                                step: speed.step,
                                forward: speed.forward,
                                emergencyStop: speed.emergencyStop,
                                busy: busy,
                                doubleTraction: db4 & 0x40 != 0,
                                smartSearch: db4 & 0x20 != 0,
                                functions: functions)
            return .locoInfo(info)
        default:
            break
        }
        return .unknown(header: Z21.Header.xbus.rawValue, payload: p)
    }

    static func bcd(_ b: UInt8) -> Int {
        return Int(b >> 4) * 10 + Int(b & 0x0F)
    }

    /// Firmware aus LAN_GET_HWINFO ist BCD-kodiert, z.B. 0x00000143 = 1.43
    public static func firmwareString(_ fw: UInt32) -> String {
        let major = bcd(UInt8((fw >> 8) & 0xFF))
        let minor = bcd(UInt8(fw & 0xFF))
        return String(format: "%d.%02d", major, minor)
    }

    public static func hardwareName(_ type: UInt32) -> String {
        switch type {
        case 0x200: return "Z21 (schwarz, alt)"
        case 0x201: return "Z21 (schwarz)"
        case 0x202: return "SmartRail"
        case 0x203: return "z21 (weiß)"
        case 0x204: return "z21start"
        case 0x205: return "10806 Z21 Single Booster"
        case 0x206: return "10807 Z21 Dual Booster"
        case 0x211: return "Z21 XL Series"
        case 0x212: return "Z21 XL Booster"
        case 0x301: return "Z21 Switch Decoder"
        case 0x302: return "Z21 Signal Decoder"
        default: return String(format: "Unbekannt (0x%03X)", type)
        }
    }
}
