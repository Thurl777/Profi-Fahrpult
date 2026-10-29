import Foundation

/// Position eines Belegtmelders auf der Kontakt-Messstrecke (Dauerkontakte wie bei iTrain).
public enum ContactPosition: Hashable {
    case left
    case middle
    case right
}

/// Ergebnis einer vollständigen Durchfahrt über alle drei Melder
public struct ContactRun: Equatable {
    public let kmh: Double
    public let forward: Bool

    public init(kmh: Double, forward: Bool) {
        self.kmh = kmh
        self.forward = forward
    }
}

/// Wertet die steigenden Flanken dreier Belegtmelder (links, Mitte, rechts) aus und berechnet daraus
/// die Maßstabsgeschwindigkeit, ähnlich der Messung mit Dauerkontakten in iTrain: Die Lok fährt über die
/// Messstrecke, die Zeit zwischen den Auslösepunkten liefert zusammen mit den eingegebenen Streckenlängen
/// die Geschwindigkeit je Abschnitt; aus beiden Abschnitten wird gemittelt.
public final class ContactSpeedMeasurer {

    public var distanceLeftMiddleCm: Double
    public var distanceMiddleRightCm: Double
    public var scale: ModelScale

    /// Eine begonnene Durchfahrt wird verworfen, wenn sie länger als diese Zeit dauert (Lok stehen geblieben o.ä.)
    public var timeoutSeconds: Double = 20

    /// Schnellere Durchfahrten werden verworfen: Sie entstehen, wenn mehrere Melder im selben
    /// Augenblick gemeldet werden (z.B. erste Rückmeldung der Z21 oder lange Lok über allen Meldern).
    public var maxPlausibleKmh: Double = SpeedPoint.maxKmh

    private var sequence: [ContactPosition] = []
    private var times: [ContactPosition: Double] = [:]

    public init(distanceLeftMiddleCm: Double, distanceMiddleRightCm: Double, scale: ModelScale) {
        self.distanceLeftMiddleCm = distanceLeftMiddleCm
        self.distanceMiddleRightCm = distanceMiddleRightCm
        self.scale = scale
    }

    public func reset() {
        sequence = []
        times = [:]
    }

    /// Steigende Flanke eines Melders (wird belegt). `time` ist ein monoton steigender Zeitstempel in Sekunden
    /// (z.B. CACurrentMediaTime()). Liefert ein Ergebnis, sobald links–Mitte–rechts (oder umgekehrt) vollständig
    /// durchfahren wurde.
    @discardableResult
    public func occupied(_ position: ContactPosition, at time: Double) -> ContactRun? {
        if let first = sequence.first, let firstTime = times[first], time - firstTime > timeoutSeconds {
            reset()
        }
        if sequence.last == position { return nil }
        sequence.append(position)
        times[position] = time
        guard sequence.count >= 3 else { return nil }
        let last3 = Array(sequence.suffix(3))
        let result = evaluate(last3)
        reset()
        return result
    }

    private func evaluate(_ seq: [ContactPosition]) -> ContactRun? {
        let forward: Bool
        if seq == [.left, .middle, .right] {
            forward = true
        } else if seq == [.right, .middle, .left] {
            forward = false
        } else {
            return nil
        }
        guard let t1 = times[seq[0]], let t2 = times[seq[1]], let t3 = times[seq[2]] else { return nil }
        let d1 = forward ? distanceLeftMiddleCm : distanceMiddleRightCm
        let d2 = forward ? distanceMiddleRightCm : distanceLeftMiddleCm
        let dt1 = t2 - t1
        let dt2 = t3 - t2
        guard dt1 > 0, dt2 > 0,
              let v1 = scale.scaleSpeed(distanceCm: d1, seconds: dt1),
              let v2 = scale.scaleSpeed(distanceCm: d2, seconds: dt2),
              v1 <= maxPlausibleKmh, v2 <= maxPlausibleKmh else { return nil }
        return ContactRun(kmh: (v1 + v2) / 2, forward: forward)
    }
}
