import Foundation

/// Symbole für Funktionstasten (werden in FunctionIconRenderer gezeichnet)
enum FunctionIcon: String, Codable, CaseIterable {
    case generic
    case light
    case lightRear
    case highBeam
    case cabLight
    case interiorLight
    case sound
    case mute
    case horn
    case whistle
    case bell
    case announcement
    case shunting
    case coupler
    case smoke
    case brake
    case fan
    case door
    case pantograph

    var title: String {
        switch self {
        case .generic: return "Allgemein"
        case .light: return "Licht"
        case .lightRear: return "Rücklicht"
        case .highBeam: return "Fernlicht"
        case .cabLight: return "Führerstand"
        case .interiorLight: return "Innenbeleuchtung"
        case .sound: return "Fahrgeräusch"
        case .mute: return "Stumm"
        case .horn: return "Horn"
        case .whistle: return "Pfeife"
        case .bell: return "Glocke"
        case .announcement: return "Ansage"
        case .shunting: return "Rangiergang"
        case .coupler: return "Kupplung"
        case .smoke: return "Rauch"
        case .brake: return "Bremse"
        case .fan: return "Lüfter"
        case .door: return "Türen"
        case .pantograph: return "Pantograf"
        }
    }
}

struct LocoFunction: Codable, Equatable {
    var index: Int
    var name: String
    var icon: FunctionIcon
    /// Moment-Funktion: aktiv nur solange die Taste gedrückt ist
    var momentary: Bool
}

struct Locomotive: Codable, Equatable {
    static let functionCount = 32

    var id: String
    var name: String
    var address: UInt16
    var speedSteps: SpeedSteps
    /// Maßstabsgeschwindigkeit bei der höchsten Fahrstufe (gilt, solange keine Messpunkte vorhanden sind)
    var maxSpeedKmh: Int
    /// Eingemessene Geschwindigkeiten; optional, damit ältere Lokdateien weiter geladen werden
    var speedPoints: [SpeedPoint]?
    /// Dateiname des Lokbildes im Dokumentenordner
    var imageFile: String?
    var functions: [LocoFunction]

    init(name: String, address: UInt16, speedSteps: SpeedSteps = .steps128) {
        self.id = UUID().uuidString
        self.name = name
        self.address = address
        self.speedSteps = speedSteps
        self.maxSpeedKmh = 120
        self.imageFile = nil
        self.functions = Locomotive.defaultFunctions()
    }

    static func defaultFunctions() -> [LocoFunction] {
        var list: [LocoFunction] = []
        for i in 0..<functionCount {
            var icon = FunctionIcon.generic
            var name = "Funktion \(i)"
            switch i {
            case 0: icon = .light; name = "Licht"
            case 1: icon = .sound; name = "Fahrgeräusch"
            case 2: icon = .horn; name = "Horn"
            case 3: icon = .bell; name = "Glocke"
            case 4: icon = .shunting; name = "Rangiergang"
            default: break
            }
            list.append(LocoFunction(index: i, name: name, icon: icon, momentary: i == 2))
        }
        return list
    }

    /// Umrechnung Fahrstufe -> km/h für Tacho und Lokliste
    var speedCurve: SpeedCurve {
        return SpeedCurve(points: speedPoints ?? [], maxStep: speedSteps.maxStep, fallbackMaxKmh: Double(maxSpeedKmh))
    }

    func function(_ index: Int) -> LocoFunction {
        if let f = functions.first(where: { $0.index == index }) { return f }
        return LocoFunction(index: index, name: "Funktion \(index)", icon: .generic, momentary: false)
    }

    mutating func setFunction(_ f: LocoFunction) {
        if let i = functions.firstIndex(where: { $0.index == f.index }) {
            functions[i] = f
        } else {
            functions.append(f)
            functions.sort { $0.index < $1.index }
        }
    }
}
