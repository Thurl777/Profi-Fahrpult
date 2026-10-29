import Foundation

enum StopButtonMode: Int {
    /// Gleisspannung aus (wie die STOP-Taste der ECoS)
    case trackPowerOff = 0
    /// Nothalt aller Loks, Gleisspannung bleibt an
    case emergencyStop = 1
}

final class AppSettings {

    static let shared = AppSettings()
    static let throttleCount = 2

    private let defaults = UserDefaults.standard

    private enum Key {
        static let host = "z21.host"
        static let port = "z21.port"
        static let stopMode = "ui.stopMode"
        static let keepScreenOn = "ui.keepScreenOn"
        static let turnoutTime = "z21.turnoutTime"
        static let directionStops = "ui.directionStops"
        static let throttlePrefix = "ui.throttle."
        static let accessoryPage = "ui.accessoryPage"
        static let autoConnect = "z21.autoConnect"
        static let modelScale = "measure.scale"
        static let measureDistance = "measure.distanceCm"
        static let followHandhelds = "ui.followHandhelds"
    }

    private init() {
        defaults.register(defaults: [
            Key.host: Z21.defaultHost,
            Key.port: Int(Z21.defaultPort),
            Key.stopMode: StopButtonMode.trackPowerOff.rawValue,
            Key.keepScreenOn: true,
            Key.turnoutTime: 150,
            Key.directionStops: true,
            Key.accessoryPage: 0,
            Key.autoConnect: true,
            Key.modelScale: ModelScale.h0.rawValue,
            Key.measureDistance: 100.0,
            Key.followHandhelds: true
        ])
    }

    var host: String {
        get { return defaults.string(forKey: Key.host) ?? Z21.defaultHost }
        set { defaults.set(newValue, forKey: Key.host) }
    }

    var port: UInt16 {
        get {
            let p = defaults.integer(forKey: Key.port)
            return (p > 0 && p < 65536) ? UInt16(p) : Z21.defaultPort
        }
        set { defaults.set(Int(newValue), forKey: Key.port) }
    }

    var autoConnect: Bool {
        get { return defaults.bool(forKey: Key.autoConnect) }
        set { defaults.set(newValue, forKey: Key.autoConnect) }
    }

    var stopButtonMode: StopButtonMode {
        get { return StopButtonMode(rawValue: defaults.integer(forKey: Key.stopMode)) ?? .trackPowerOff }
        set { defaults.set(newValue.rawValue, forKey: Key.stopMode) }
    }

    var keepScreenOn: Bool {
        get { return defaults.bool(forKey: Key.keepScreenOn) }
        set { defaults.set(newValue, forKey: Key.keepScreenOn) }
    }

    /// Schaltzeit für Weichenausgänge in ms
    var turnoutSwitchTime: Int {
        get { return max(50, min(defaults.integer(forKey: Key.turnoutTime), 2000)) }
        set { defaults.set(newValue, forKey: Key.turnoutTime) }
    }

    /// Richtungswechsel bei fahrender Lok hält die Lok zuerst an
    var directionChangeStops: Bool {
        get { return defaults.bool(forKey: Key.directionStops) }
        set { defaults.set(newValue, forKey: Key.directionStops) }
    }

    var accessoryPage: Int {
        get { return defaults.integer(forKey: Key.accessoryPage) }
        set { defaults.set(newValue, forKey: Key.accessoryPage) }
    }

    /// Maßstab der Anlage für die Einmess-Hilfe
    var modelScale: ModelScale {
        get { return ModelScale(rawValue: defaults.string(forKey: Key.modelScale) ?? "") ?? .h0 }
        set { defaults.set(newValue.rawValue, forKey: Key.modelScale) }
    }

    /// Länge der Messstrecke in cm
    var measureDistanceCm: Double {
        get {
            let d = defaults.double(forKey: Key.measureDistance)
            return d > 0 ? d : 100
        }
        set { defaults.set(newValue, forKey: Key.measureDistance) }
    }

    /// Regler übernehmen eine Lok, sobald sie an einer Multimaus (oder einem anderen Gerät) bedient wird
    var followHandhelds: Bool {
        get { return defaults.bool(forKey: Key.followHandhelds) }
        set { defaults.set(newValue, forKey: Key.followHandhelds) }
    }

    func throttleLocoID(_ throttle: Int) -> String? {
        return defaults.string(forKey: Key.throttlePrefix + "\(throttle)")
    }

    func setThrottleLocoID(_ id: String?, for throttle: Int) {
        defaults.set(id, forKey: Key.throttlePrefix + "\(throttle)")
        NotificationCenter.default.post(name: .throttleAssignmentChanged, object: self,
                                        userInfo: ["throttle": throttle])
    }

    /// Tauscht die Loks der beiden Regler
    func swapThrottleLocos() {
        let first = throttleLocoID(0)
        defaults.set(throttleLocoID(1), forKey: Key.throttlePrefix + "0")
        defaults.set(first, forKey: Key.throttlePrefix + "1")
        NotificationCenter.default.post(name: .throttleAssignmentChanged, object: self,
                                        userInfo: ["swapped": true])
    }
}
