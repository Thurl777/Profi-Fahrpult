import Foundation

/// Ein gemessener Punkt der Geschwindigkeitskennlinie einer Lok.
/// Die Fahrstufe wird relativ (0…1) gespeichert, damit die Punkte beim Wechsel
/// zwischen 14, 28 und 128 Fahrstufen erhalten bleiben.
public struct SpeedPoint: Codable, Equatable {
    /// Höchste Maßstabsgeschwindigkeit, die als Messwert akzeptiert wird. Höhere Werte stammen
    /// von Fehlauslösungen (z.B. zwei Melder im selben Augenblick) und werden ignoriert.
    public static let maxKmh: Double = 1000

    public var fraction: Double
    /// Maßstabsgeschwindigkeit in km/h
    public var kmh: Double

    public init(fraction: Double, kmh: Double) {
        self.fraction = max(0, min(1, fraction))
        self.kmh = max(0, kmh)
    }

    public init(step: Int, maxStep: Int, kmh: Double) {
        self.init(fraction: maxStep > 0 ? Double(step) / Double(maxStep) : 0, kmh: kmh)
    }

    public func step(maxStep: Int) -> Int {
        return Int((fraction * Double(maxStep)).rounded())
    }
}

/// Rechnet Fahrstufen in Maßstabsgeschwindigkeit um.
/// Ohne Messpunkte linear bis `fallbackMaxKmh`, sonst stückweise linear durch die Messpunkte.
public struct SpeedCurve: Equatable {
    public let points: [SpeedPoint]
    public let maxStep: Int
    public let fallbackMaxKmh: Double

    public init(points: [SpeedPoint], maxStep: Int, fallbackMaxKmh: Double) {
        // nach Fahrstufe sortieren, Fahrstufe 0 und unplausible Werte ignorieren, doppelte Fahrstufen: letzter Wert gilt
        var byFraction: [Double: SpeedPoint] = [:]
        for p in points where p.fraction > 0 && p.kmh.isFinite && p.kmh < SpeedPoint.maxKmh {
            byFraction[p.fraction] = p
        }
        self.points = byFraction.values.sorted { $0.fraction < $1.fraction }
        self.maxStep = max(1, maxStep)
        self.fallbackMaxKmh = max(0, fallbackMaxKmh)
    }

    public var hasMeasurements: Bool { return !points.isEmpty }

    public func kmh(atStep step: Int) -> Double {
        return kmh(atFraction: Double(max(0, min(step, maxStep))) / Double(maxStep))
    }

    public func kmh(atFraction f: Double) -> Double {
        guard f > 0 else { return 0 }
        guard let last = points.last else { return f * fallbackMaxKmh }

        var previous = SpeedPoint(fraction: 0, kmh: 0)
        for p in points {
            if f <= p.fraction {
                let span = p.fraction - previous.fraction
                guard span > 0 else { return p.kmh }
                return previous.kmh + (p.kmh - previous.kmh) * (f - previous.fraction) / span
            }
            previous = p
        }

        // Über dem letzten Messpunkt mit der Steigung der letzten Strecke weiterrechnen
        let before = points.count >= 2 ? points[points.count - 2] : SpeedPoint(fraction: 0, kmh: 0)
        let span = last.fraction - before.fraction
        let slope = span > 0 ? max(0, (last.kmh - before.kmh) / span) : 0
        return min(SpeedPoint.maxKmh, last.kmh + slope * (f - last.fraction))
    }

    /// Geschwindigkeit bei der höchsten Fahrstufe
    public var topSpeed: Double { return kmh(atFraction: 1) }

    /// Endwert der Tachoskala: Höchstgeschwindigkeit auf volle 10 km/h aufgerundet
    public var scaleMax: Int {
        return max(10, Int((topSpeed / 10).rounded(.up)) * 10)
    }
}

/// Modellbahn-Maßstäbe für die Umrechnung in Maßstabsgeschwindigkeit
public enum ModelScale: String, Codable, CaseIterable {
    case z
    case n
    case tt
    case h0
    case s
    case zero
    case one
    case g

    public var factor: Double {
        switch self {
        case .z: return 220
        case .n: return 160
        case .tt: return 120
        case .h0: return 87
        case .s: return 64
        case .zero: return 45
        case .one: return 32
        case .g: return 22.5
        }
    }

    public var title: String {
        switch self {
        case .z: return "Z (1:220)"
        case .n: return "N (1:160)"
        case .tt: return "TT (1:120)"
        case .h0: return "H0 (1:87)"
        case .s: return "S (1:64)"
        case .zero: return "0 (1:45)"
        case .one: return "1 (1:32)"
        case .g: return "G / IIm (1:22,5)"
        }
    }

    /// Maßstabsgeschwindigkeit in km/h für eine gemessene Strecke und Zeit.
    public func scaleSpeed(distanceCm: Double, seconds: Double) -> Double? {
        guard distanceCm > 0, seconds > 0 else { return nil }
        let metersPerSecond = distanceCm / 100 / seconds
        return metersPerSecond * 3.6 * factor
    }
}
