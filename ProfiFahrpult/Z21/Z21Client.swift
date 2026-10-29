import Foundation

/// Beobachter für Zustandsänderungen der Zentrale. Alle Aufrufe erfolgen auf dem Main-Thread.
public protocol Z21ClientObserver: AnyObject {
    func z21ClientConnectionChanged(_ client: Z21Client)
    func z21ClientTrackStatusChanged(_ client: Z21Client)
    func z21ClientInfoChanged(_ client: Z21Client)
    func z21ClientSystemStateChanged(_ client: Z21Client)
    func z21Client(_ client: Z21Client, locoChanged info: LocoInfo)
    func z21Client(_ client: Z21Client, turnoutChanged address: UInt16, position: TurnoutPosition)
    func z21Client(_ client: Z21Client, feedbackChangedInGroup group: UInt8)
    func z21Client(_ client: Z21Client, railCom data: RailComData)
}

public extension Z21ClientObserver {
    func z21ClientConnectionChanged(_ client: Z21Client) {}
    func z21ClientTrackStatusChanged(_ client: Z21Client) {}
    func z21ClientInfoChanged(_ client: Z21Client) {}
    func z21ClientSystemStateChanged(_ client: Z21Client) {}
    func z21Client(_ client: Z21Client, locoChanged info: LocoInfo) {}
    func z21Client(_ client: Z21Client, turnoutChanged address: UInt16, position: TurnoutPosition) {}
    func z21Client(_ client: Z21Client, feedbackChangedInGroup group: UInt8) {}
    func z21Client(_ client: Z21Client, railCom data: RailComData) {}
}

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

public enum TrackStatus: Equatable {
    case unknown
    case on
    case off
    case emergencyStop
    case shortCircuit
    case programming
}

public enum CVResult: Equatable {
    case value(UInt8)
    case success          // POM-Schreiben (keine Rückmeldung der Zentrale)
    case noAcknowledge    // Decoder antwortet nicht
    case shortCircuit
    case timeout
    case notConnected
}

/// Verbindung zur Roco/Fleischmann Z21 über das Z21-LAN-Protokoll (UDP Port 21105).
public final class Z21Client {

    public static let shared = Z21Client()

    // MARK: Öffentlicher Zustand

    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var trackStatus: TrackStatus = .unknown
    public private(set) var host: String = Z21.defaultHost
    public private(set) var port: UInt16 = Z21.defaultPort

    public private(set) var serialNumber: UInt32?
    public private(set) var hardwareType: UInt32?
    public private(set) var firmware: String?
    public private(set) var xbusVersion: String?
    public private(set) var systemState: SystemState?
    public private(set) var lastError: String?

    public private(set) var locos: [UInt16: LocoInfo] = [:]
    public private(set) var turnouts: [UInt16: TurnoutPosition] = [:]
    /// 20 Bytes: R-Bus-Module 1...20, je 8 Eingänge
    public private(set) var feedback: [UInt8] = Array(repeating: 0, count: 20)
    public private(set) var railCom: [UInt16: RailComData] = [:]

    /// Dauer, die ein Weichenausgang aktiv bleibt (ms)
    public var turnoutSwitchTime: Int = 150

    // MARK: Intern

    private let socket = UDPSocket(callbackQueue: .main)
    private var observers: [WeakObserver] = []
    private var timer: DispatchSourceTimer?
    private var lastReceive: Date?
    private var tick = 0
    private var subscribedLocos: [UInt16] = []
    private var pendingCV: ((CVResult) -> Void)?
    private var pendingCVTimeout: DispatchWorkItem?

    /// Nach dieser Zeit ohne Antwort gilt die Verbindung als verloren
    private let connectionTimeout: TimeInterval = 5
    private let cvTimeout: TimeInterval = 15

    public init() {
        socket.onReceive = { [weak self] data in
            self?.handle(data)
        }
    }

    // MARK: - Beobachter

    public func addObserver(_ observer: Z21ClientObserver) {
        observers = observers.filter { $0.value != nil && $0.value !== observer }
        observers.append(WeakObserver(observer))
    }

    public func removeObserver(_ observer: Z21ClientObserver) {
        observers = observers.filter { $0.value != nil && $0.value !== observer }
    }

    private func notify(_ block: (Z21ClientObserver) -> Void) {
        for o in observers {
            if let v = o.value { block(v) }
        }
    }

    // MARK: - Verbindung

    public func connect(host: String, port: UInt16 = Z21.defaultPort) {
        disconnect(sendLogoff: connectionState == .connected)
        self.host = host
        self.port = port
        lastError = nil
        do {
            try socket.open(host: host, port: port)
        } catch {
            lastError = "\(error)"
            setConnectionState(.disconnected)
            return
        }
        lastReceive = nil
        setConnectionState(.connecting)
        sendHandshake()
        startTimer()
    }

    public func disconnect(sendLogoff: Bool = true) {
        if sendLogoff && socket.isOpen {
            socket.send(Z21Codec.logoff())
        }
        stopTimer()
        socket.close()
        finishCV(.notConnected)
        trackStatus = .unknown
        setConnectionState(.disconnected)
    }

    private func setConnectionState(_ state: ConnectionState) {
        guard state != connectionState else { return }
        connectionState = state
        notify { $0.z21ClientConnectionChanged(self) }
    }

    private func sendHandshake() {
        send(Z21Codec.setBroadcastFlags([.drivingAndSwitching, .rmBus, .systemState, .railComSubscribed]))
        send(Z21Codec.getSerialNumber())
        send(Z21Codec.getHardwareInfo())
        send(Z21Codec.getXBusVersion())
        send(Z21Codec.getFirmwareVersion())
        send(Z21Codec.getStatus())
        send(Z21Codec.systemStateGetData())
        for address in subscribedLocos {
            send(Z21Codec.getLocoInfo(address: address))
        }
    }

    private func startTimer() {
        stopTimer()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.onTimer() }
        timer = t
        t.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func onTimer() {
        tick += 1
        switch connectionState {
        case .connected:
            if let last = lastReceive, Date().timeIntervalSince(last) > connectionTimeout {
                // Verbindung verloren – erneut versuchen
                trackStatus = .unknown
                setConnectionState(.connecting)
                notify { $0.z21ClientTrackStatusChanged(self) }
            } else if tick % 2 == 0 {
                // Abfrage dient zugleich als Keep-Alive (Z21 meldet Clients nach 60 s Inaktivität ab)
                send(Z21Codec.systemStateGetData())
            }
        case .connecting:
            if tick % 2 == 0 { sendHandshake() }
        case .disconnected:
            break
        }
    }

    @discardableResult
    private func send(_ data: Data) -> Bool {
        return socket.send(data)
    }

    // MARK: - Gleisspannung

    public func setTrackPower(_ on: Bool) {
        send(on ? Z21Codec.setTrackPowerOn() : Z21Codec.setTrackPowerOff())
    }

    /// Nothalt aller Loks, die Gleisspannung bleibt eingeschaltet
    public func emergencyStopAll() {
        send(Z21Codec.setStop())
    }

    // MARK: - Loks

    /// Lok abonnieren: die Zentrale meldet danach Änderungen dieser Lok (max. 16 pro Client).
    public func subscribeLoco(_ address: UInt16) {
        guard address > 0 else { return }
        subscribedLocos.removeAll { $0 == address }
        subscribedLocos.append(address)
        if subscribedLocos.count > 16 { subscribedLocos.removeFirst() }
        send(Z21Codec.getLocoInfo(address: address))
    }

    public func requestLocoInfo(_ address: UInt16) {
        send(Z21Codec.getLocoInfo(address: address))
    }

    public func locoInfo(_ address: UInt16) -> LocoInfo? {
        return locos[address]
    }

    public func setLocoDrive(address: UInt16, speedSteps: SpeedSteps, step: Int, forward: Bool) {
        guard address > 0 else { return }
        send(Z21Codec.setLocoDrive(address: address, speedSteps: speedSteps, step: step, forward: forward))
        var info = locos[address] ?? LocoInfo(address: address, speedSteps: speedSteps)
        info.speedSteps = speedSteps
        info.step = max(0, min(step, speedSteps.maxStep))
        info.forward = forward
        info.emergencyStop = false
        updateLoco(info)
    }

    public func emergencyStopLoco(_ address: UInt16) {
        guard address > 0 else { return }
        send(Z21Codec.setLocoEmergencyStop(address: address))
        if var info = locos[address] {
            info.step = 0
            info.emergencyStop = true
            updateLoco(info)
        }
    }

    public func setLocoFunction(address: UInt16, function: Int, on: Bool) {
        guard address > 0 else { return }
        send(Z21Codec.setLocoFunction(address: address, function: function, action: on ? .on : .off))
        var info = locos[address] ?? LocoInfo(address: address)
        info.setFunction(function, on: on)
        updateLoco(info)
    }

    private func updateLoco(_ info: LocoInfo) {
        locos[info.address] = info
        notify { $0.z21Client(self, locoChanged: info) }
    }

    // MARK: - Weichen / Zubehör

    /// Schaltet einen Weichenausgang. Der Ausgang wird nach `turnoutSwitchTime` ms wieder deaktiviert.
    public func setTurnout(address: UInt16, output: Int) {
        guard address > 0 else { return }
        send(Z21Codec.setTurnout(address: address, output: output, activate: true))
        turnouts[address] = output == 0 ? .output1 : .output2
        notify { $0.z21Client(self, turnoutChanged: address, position: output == 0 ? .output1 : .output2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(turnoutSwitchTime)) { [weak self] in
            self?.send(Z21Codec.setTurnout(address: address, output: output, activate: false))
        }
    }

    public func requestTurnoutInfo(_ address: UInt16) {
        guard address > 0 else { return }
        send(Z21Codec.getTurnoutInfo(address: address))
    }

    // MARK: - Rückmelder

    public func requestFeedback() {
        send(Z21Codec.rmBusGetData(group: 0))
        send(Z21Codec.rmBusGetData(group: 1))
    }

    /// - Parameters:
    ///   - module: 1...20
    ///   - input: 1...8
    public func feedbackOccupied(module: Int, input: Int) -> Bool {
        guard module >= 1 && module <= feedback.count && input >= 1 && input <= 8 else { return false }
        return feedback[module - 1] & UInt8(1 << (input - 1)) != 0
    }

    // MARK: - Programmieren

    public var isProgramming: Bool { return pendingCV != nil }

    /// CV auf dem Programmiergleis lesen
    public func readCV(_ cv: UInt16, completion: @escaping (CVResult) -> Void) {
        startCV(Z21Codec.cvRead(cv: cv), completion: completion)
    }

    /// CV auf dem Programmiergleis schreiben
    public func writeCV(_ cv: UInt16, value: UInt8, completion: @escaping (CVResult) -> Void) {
        startCV(Z21Codec.cvWrite(cv: cv, value: value), completion: completion)
    }

    /// CV auf dem Hauptgleis lesen (POM, nur mit RailCom)
    public func readPOM(address: UInt16, cv: UInt16, completion: @escaping (CVResult) -> Void) {
        startCV(Z21Codec.pomReadByte(address: address, cv: cv), completion: completion)
    }

    /// CV auf dem Hauptgleis schreiben (POM). Die Zentrale bestätigt diesen Befehl nicht.
    public func writePOM(address: UInt16, cv: UInt16, value: UInt8, completion: ((CVResult) -> Void)? = nil) {
        guard connectionState == .connected else {
            completion?(.notConnected)
            return
        }
        send(Z21Codec.pomWriteByte(address: address, cv: cv, value: value))
        completion?(.success)
    }

    /// Beendet den Programmiermodus der Zentrale (schaltet das Hauptgleis wieder ein)
    public func leaveProgrammingMode() {
        setTrackPower(true)
    }

    private func startCV(_ command: Data, completion: @escaping (CVResult) -> Void) {
        guard connectionState == .connected else {
            completion(.notConnected)
            return
        }
        finishCV(.timeout)
        pendingCV = completion
        let work = DispatchWorkItem { [weak self] in self?.finishCV(.timeout) }
        pendingCVTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + cvTimeout, execute: work)
        send(command)
    }

    private func finishCV(_ result: CVResult) {
        pendingCVTimeout?.cancel()
        pendingCVTimeout = nil
        if let completion = pendingCV {
            pendingCV = nil
            completion(result)
        }
    }

    // MARK: - Empfang

    func handle(_ data: Data) {
        let messages = Z21Codec.parse(data)
        guard !messages.isEmpty else { return }
        lastReceive = Date()
        if connectionState != .connected && socket.isOpen {
            setConnectionState(.connected)
        }
        for message in messages {
            handle(message)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func handle(_ message: Z21Message) {
        switch message {
        case .serialNumber(let sn):
            serialNumber = sn
            notify { $0.z21ClientInfoChanged(self) }
        case .hardwareInfo(let type, let fw):
            hardwareType = type
            firmware = Z21Codec.firmwareString(fw)
            notify { $0.z21ClientInfoChanged(self) }
        case .firmwareVersion(let major, let minor):
            if firmware == nil {
                firmware = String(format: "%d.%02d", major, minor)
                notify { $0.z21ClientInfoChanged(self) }
            }
        case .xbusVersion(let version, _):
            xbusVersion = String(format: "%d.%d", version >> 4, version & 0x0F)
            notify { $0.z21ClientInfoChanged(self) }
        case .trackPowerOn:
            setTrackStatus(.on)
        case .trackPowerOff:
            setTrackStatus(.off)
        case .programmingMode:
            setTrackStatus(.programming)
        case .trackShortCircuit:
            setTrackStatus(.shortCircuit)
        case .emergencyStopped:
            setTrackStatus(.emergencyStop)
            for (address, var info) in locos where info.step != 0 {
                info.step = 0
                locos[address] = info
                notify { $0.z21Client(self, locoChanged: info) }
            }
        case .statusChanged(let state):
            setTrackStatus(Z21Client.trackStatus(from: state))
        case .systemState(let state):
            systemState = state
            setTrackStatus(Z21Client.trackStatus(from: state.centralState))
            notify { $0.z21ClientSystemStateChanged(self) }
        case .locoInfo(let info):
            locos[info.address] = info
            notify { $0.z21Client(self, locoChanged: info) }
        case .turnoutInfo(let address, let position):
            turnouts[address] = position
            notify { $0.z21Client(self, turnoutChanged: address, position: position) }
        case .cvResult(_, let value):
            finishCV(.value(value))
        case .cvNack:
            finishCV(.noAcknowledge)
        case .cvNackShortCircuit:
            finishCV(.shortCircuit)
        case .rmBus(let group, let data):
            let start = Int(group) * 10
            for (i, b) in data.enumerated() where start + i < feedback.count {
                feedback[start + i] = b
            }
            notify { $0.z21Client(self, feedbackChangedInGroup: group) }
        case .railCom(let data):
            railCom[data.address] = data
            notify { $0.z21Client(self, railCom: data) }
        case .code, .broadcastFlags, .locoMode, .turnoutMode, .unknownCommand, .unknown:
            break
        }
    }

    static func trackStatus(from state: Z21.CentralState) -> TrackStatus {
        if state.contains(.shortCircuit) { return .shortCircuit }
        if state.contains(.programmingModeActive) { return .programming }
        if state.contains(.trackVoltageOff) { return .off }
        if state.contains(.emergencyStop) { return .emergencyStop }
        return .on
    }

    private func setTrackStatus(_ status: TrackStatus) {
        guard status != trackStatus else { return }
        trackStatus = status
        notify { $0.z21ClientTrackStatusChanged(self) }
    }
}

private struct WeakObserver {
    weak var value: Z21ClientObserver?
    init(_ value: Z21ClientObserver) { self.value = value }
}
