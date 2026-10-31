import Foundation

/// Bewegt die Tachonadel wie die Geschwindigkeit einer echten Lok, statt von Fahrstufe zu Fahrstufe
/// zu springen. Die App rechnet mit dem Anteil der höchsten Fahrstufe (0…1).
///
/// Da die Nadel eine Geschwindigkeit anzeigt, entspricht ihre Drehgeschwindigkeit der Beschleunigung
/// der Lok. Das Modell folgt deshalb der Zugkraftkennlinie einer Lok:
/// - **Anfahrzugkraft:** Unterhalb von `transitionSpeed` beschleunigt die Lok gleichmäßig
///   (Zugkraft durch die Haftung begrenzt).
/// - **Leistungsgrenze:** Darüber nimmt die Beschleunigung mit 1/v ab (Zugkraft = Leistung ÷ Geschwindigkeit),
///   das obere Drittel des Tachos dauert also länger als das untere.
/// - **Bremsen:** gleichmäßige Verzögerung über den ganzen Geschwindigkeitsbereich.
/// - **Trägheit:** Die Beschleunigung baut sich bei jeder Änderung erst langsam auf (Zugkraftaufbau,
///   Ruckbegrenzung) und vor dem Ziel wieder ab – die Nadel läuft weich an und kommt weich zum Stehen.
///
/// Die Dauer hängt damit von der Größe der Änderung ab: 0 auf halbe Geschwindigkeit dauert
/// ungefähr halb so lange wie 0 auf Höchstgeschwindigkeit.
///
/// Umsetzung: Ein Leitwert läuft mit der Beschleunigung aus der Zugkraftkennlinie zum Ziel,
/// die Nadel folgt ihm über eine kritisch gedämpfte Feder. Deren Sprungantwort ist nie negativ,
/// darum überschwingt die Nadel nicht.
public struct NeedleDamper {

    /// Einziger Einstellwert: ungefähre Zeit in Sekunden für den vollen Ausschlag von 0 bis zur
    /// Höchstgeschwindigkeit. Kleinere Änderungen dauern entsprechend kürzer.
    public var delay: Double
    public private(set) var value: Double
    public var target: Double
    /// Drehgeschwindigkeit der Nadel in Anteil pro Sekunde (= Beschleunigung der Lok)
    public private(set) var velocity: Double = 0
    /// Leitwert, dem die Nadel mit Trägheit folgt
    public private(set) var reference: Double

    /// Unterhalb dieses Abstands rastet die Nadel auf dem Ziel ein (0,2 % des Zeigerwegs)
    public static let snapDistance = 0.002
    /// Übergang von der Anfahrzugkraft zur Leistungsgrenze (Anteil der Höchstgeschwindigkeit)
    public static let transitionSpeed = 0.5
    /// Trägheit beim Anfahren als Anteil von `delay` (Zeitkonstante der Feder bei großen Änderungen)
    private static let inertiaShare = 0.1
    /// Bei kleinen Änderungen reagiert die Nadel bis zu diesem Faktor schneller
    private static let minInertiaScale = 0.4
    /// Anteil von `delay`, den der Leitwert für 0 → Höchstgeschwindigkeit braucht;
    /// den Rest macht das weiche Anlaufen und Auslaufen der Nadel aus
    private static let rampShare = 0.82

    public init(value: Double = 0, delay: Double = 2) {
        self.value = value
        self.target = value
        self.reference = value
        self.delay = delay
    }

    public var isSettled: Bool {
        return value == target && reference == target && velocity == 0
    }

    /// Ohne Gleiten direkt auf `newValue` stellen (Lokwechsel, Nothalt)
    public mutating func jump(to newValue: Double) {
        value = newValue
        target = newValue
        reference = newValue
        velocity = 0
    }

    /// Beschleunigung bei niedriger Geschwindigkeit in Anteil pro Sekunde², so gewählt, dass der
    /// Leitwert 0 → 1 in `rampShare · delay` schafft:
    /// vₜ/a + (1 − vₜ²)/(2·a·vₜ) = (1 + vₜ²)/(2·a·vₜ)
    private var startAcceleration: Double {
        let vt = NeedleDamper.transitionSpeed
        return (1 + vt * vt) / (2 * vt) / (delay * NeedleDamper.rampShare)
    }

    /// Beschleunigung bzw. Verzögerung der Lok bei der Geschwindigkeit `speed` (Anteil 0…1)
    private func acceleration(at speed: Double, speedingUp: Bool) -> Double {
        let a = startAcceleration
        guard speedingUp else { return a }
        let vt = NeedleDamper.transitionSpeed
        return a * min(1, vt / max(abs(speed), 1e-9))
    }

    /// Rechnet die Nadel um `dt` Sekunden weiter und liefert die neue Stellung
    @discardableResult
    public mutating func advance(by dt: Double) -> Double {
        guard dt > 0, !isSettled else { return value }
        guard delay > 0.01 else {
            jump(to: target)
            return value
        }

        // Ziel liegt zwischen Nadel und Leitwert (Richtungswechsel während der Fahrt):
        // Leitwert zurücknehmen, damit die Nadel nicht über das Ziel hinausläuft
        if (target - value) * (target - reference) < 0 {
            reference = target
        }

        // Leitwert mit der Beschleunigung aus der Zugkraftkennlinie zum Ziel führen
        let toGo = target - reference
        if toGo != 0 {
            let speedingUp = abs(target) > abs(reference)
            let stepSize = acceleration(at: reference, speedingUp: speedingUp) * dt
            reference = abs(toGo) <= stepSize ? target : reference + (toGo > 0 ? stepSize : -stepSize)
        }

        // Nadel folgt dem Leitwert über eine kritisch gedämpfte Feder (exakte Lösung über `dt`,
        // wie SmoothDamp, Game Programming Gems 4). Kleine Änderungen reagieren etwas lebhafter.
        let distance = abs(target - value)
        let inertiaScale = min(1, max(NeedleDamper.minInertiaScale, distance.squareRoot()))
        let omega = 1 / (NeedleDamper.inertiaShare * delay * inertiaScale)
        let decay = exp(-omega * dt)
        let change = value - reference
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        var next = reference + (change + temp) * decay

        // Nicht über das Ziel hinausschießen
        if (target - value) * (target - next) < 0 {
            next = target
            reference = target
            velocity = 0
        }
        value = next
        if reference == target && abs(target - value) < NeedleDamper.snapDistance {
            jump(to: target)
        }
        return value
    }
}
