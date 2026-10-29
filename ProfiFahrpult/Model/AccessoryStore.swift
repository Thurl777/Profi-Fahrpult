import Foundation

enum AccessoryKind: String, Codable, CaseIterable {
    case turnoutLeft
    case turnoutRight
    case signal
    case decoupler
    case light
    case generic

    var title: String {
        switch self {
        case .turnoutLeft: return "Weiche links"
        case .turnoutRight: return "Weiche rechts"
        case .signal: return "Signal"
        case .decoupler: return "Entkuppler"
        case .light: return "Beleuchtung"
        case .generic: return "Schaltartikel"
        }
    }
}

struct AccessoryConfig: Codable, Equatable {
    var name: String
    var kind: AccessoryKind
    /// Ausgänge vertauschen (rot/grün)
    var inverted: Bool

    static func standard(address: UInt16) -> AccessoryConfig {
        return AccessoryConfig(name: "", kind: .turnoutLeft, inverted: false)
    }
}

/// Konfiguration der Magnetartikel (Name, Symbol), gespeichert als JSON.
final class AccessoryStore {

    static let shared = AccessoryStore()
    static let maxAddress: UInt16 = 2048

    private var configs: [String: AccessoryConfig] = [:]
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("accessories.json")
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([String: AccessoryConfig].self, from: data) {
            configs = dict
        }
    }

    func config(_ address: UInt16) -> AccessoryConfig {
        return configs["\(address)"] ?? AccessoryConfig.standard(address: address)
    }

    func setConfig(_ config: AccessoryConfig, for address: UInt16) {
        configs["\(address)"] = config
        if let data = try? JSONEncoder().encode(configs) {
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .accessoryStoreChanged, object: self)
    }
}
