import Foundation

/// Lässt die Tachonadel gleichmäßig zur eingestellten Fahrstufe gleiten, statt von Stufe zu Stufe
/// zu springen: kritisch gedämpfte Feder, die sanft anläuft, sanft abbremst und nicht überschwingt.
/// Die App rechnet mit dem Anteil der höchsten Fahrstufe (0…1).
public struct NeedleDamper {

    /// Ungefähre Zeit in Sekunden, bis die Nadel nach einer Änderung am Ziel steht
    /// (nach dieser Zeit sind 98 % des Wegs zurückgelegt)
    public var delay: Double
    public private(set) var value: Double
    public var target: Double
    public private(set) var velocity: Double = 0

    /// Unterhalb dieses Abstands rastet die Nadel auf dem Ziel ein (0,2 % des Zeigerwegs)
    public static let snapDistance = 0.002
    /// (1 + a)·e^(−a) = 0,02: nach `delay` Sekunden bleiben 2 % des Wegs übrig
    private static let settleFactor = 5.8

    public init(value: Double = 0, delay: Double = 1) {
        self.value = value
        self.target = value
        self.delay = delay
    }

    public var isSettled: Bool {
        return value == target && velocity == 0
    }

    /// Ohne Gleiten direkt auf `newValue` stellen (Lokwechsel, Nothalt)
    public mutating func jump(to newValue: Double) {
        value = newValue
        target = newValue
        velocity = 0
    }

    /// Rechnet die Nadel um `dt` Sekunden weiter und liefert die neue Stellung
    @discardableResult
    public mutating func advance(by dt: Double) -> Double {
        guard dt > 0, !isSettled else { return value }
        guard delay > 0.01 else {
            jump(to: target)
            return value
        }
        // Exakte Lösung der kritisch gedämpften Schwingung über `dt` (wie SmoothDamp, Game Programming Gems 4)
        let omega = NeedleDamper.settleFactor / delay
        let decay = exp(-omega * dt)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        var next = target + (change + temp) * decay
        // Nicht über das Ziel hinausschießen
        if (target - value > 0) == (next > target) {
            next = target
            velocity = 0
        }
        value = next
        if abs(target - value) < NeedleDamper.snapDistance {
            jump(to: target)
        }
        return value
    }
}
