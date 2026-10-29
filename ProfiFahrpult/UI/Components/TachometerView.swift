import UIKit

/// Rundinstrument wie der Tacho der ECoS: schwarzes Zifferblatt mit grauem Ring,
/// weißen Teilstrichen und gelbem Zeiger. Wird wie ein Drehknopf bedient:
/// eine kreisende Bewegung auf dem Instrument ändert die Fahrstufe relativ.
final class TachometerView: UIControl {

    var maxStep: Int = 126 {
        didSet {
            step = min(step, maxStep)
            setNeedsDisplay()
        }
    }

    var step: Int = 0 {
        didSet {
            if oldValue != step {
                accumulated = Double(step)
                setNeedsDisplay()
            }
        }
    }

    /// km/h bei höchster Fahrstufe, solange keine Kennlinie gesetzt ist
    var maxSpeedKmh: Int = 120 { didSet { setNeedsDisplay() } }
    /// Eingemessene Kennlinie der Lok. Zeiger und Anzeige folgen dann der Maßstabsgeschwindigkeit.
    var speedCurve: SpeedCurve? { didSet { setNeedsDisplay() } }
    var forward: Bool = true { didSet { setNeedsDisplay() } }
    var emergencyStop: Bool = false { didSet { setNeedsDisplay() } }
    /// Schaltet das Instrument bei fehlender Lok/Verbindung grau
    var isActive: Bool = true { didSet { setNeedsDisplay() } }

    private let startAngle = CGFloat.pi * 0.75
    private let sweep = CGFloat.pi * 1.5
    private var lastAngle: CGFloat = 0
    private var accumulated: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private var dialCenter: CGPoint { return CGPoint(x: bounds.midX, y: bounds.midY) }
    private var radius: CGFloat { return min(bounds.width, bounds.height) / 2 - 1 }

    // MARK: Bedienung

    private func angle(of point: CGPoint) -> CGFloat {
        return atan2(point.y - dialCenter.y, point.x - dialCenter.x)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        let p = touch.location(in: self)
        let dist = hypot(p.x - dialCenter.x, p.y - dialCenter.y)
        guard dist <= radius * 1.05 else { return false }
        lastAngle = angle(of: p)
        accumulated = Double(step)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let p = touch.location(in: self)
        let dist = hypot(p.x - dialCenter.x, p.y - dialCenter.y)
        let a = angle(of: p)
        // Nahe der Mitte ist der Winkel instabil
        guard dist > radius * 0.15 else {
            lastAngle = a
            return true
        }
        var delta = a - lastAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        lastAngle = a
        accumulated += Double(delta / sweep) * Double(maxStep)
        accumulated = max(0, min(Double(maxStep), accumulated))
        let newStep = Int(accumulated.rounded())
        if newStep != step {
            let acc = accumulated
            step = newStep
            accumulated = acc
            emergencyStop = false
            sendActions(for: .valueChanged)
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        accumulated = Double(step)
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        accumulated = Double(step)
        sendActions(for: .editingDidEnd)
    }

    // MARK: Zeichnen

    /// Einteilung der Skala wie an der ECoS: ein Strich je Teilung, jeder zweite länger,
    /// jeder vierte am längsten. Beschriftet werden 0, der Endwert und – wenn es aufgeht –
    /// die Drittel (0 40 80 120 bei 24 Strichen) oder die Hälfte (0 14 28 bei 28 Strichen).
    static func scaleLayout(_ scale: Double) -> (ticks: Int, labelEvery: Int) {
        let niceUnits: [Double] = [0.5, 1, 2, 2.5, 5, 10, 12.5, 20, 25, 50, 100]
        let preferred = [24, 28, 20, 32, 30, 36, 16, 40]
        let candidates = preferred + stride(from: 16, through: 48, by: 2).filter { !preferred.contains($0) }
        func labelEvery(_ n: Int) -> Int {
            if n % 3 == 0 && (n / 3) % 2 == 0 { return n / 3 }
            if n % 4 == 0 && (n / 4) % 4 == 0 { return n / 4 }
            return n / 2
        }
        for n in candidates {
            let unit = scale / Double(n)
            guard niceUnits.contains(where: { abs($0 - unit) < 0.0001 }) else { continue }
            let label = scale * Double(labelEvery(n)) / Double(n)
            if abs(label - label.rounded()) < 0.0001 {
                return (n, labelEvery(n))
            }
        }
        return (24, 8)
    }

    /// Endwert der Skala und aktuelle Geschwindigkeit in km/h
    private func speedValues() -> (scale: Double, current: Double) {
        let stepFraction = maxStep > 0 ? Double(step) / Double(maxStep) : 0
        if let curve = speedCurve, curve.hasMeasurements {
            return (Double(curve.scaleMax), curve.kmh(atFraction: stepFraction))
        }
        let scale = Double(max(maxSpeedKmh, 1))
        return (scale, scale * stepFraction)
    }

    private func point(at angle: CGFloat, radius r: CGFloat) -> CGPoint {
        return CGPoint(x: dialCenter.x + cos(angle) * r, y: dialCenter.y + sin(angle) * r)
    }

    private func fillCircle(radius: CGFloat, color: UIColor) {
        let c = dialCenter
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius)).fill()
    }

    // Alle Maße sind vom Display der ECoS abgenommen (Tacho mit 254 px Durchmesser) und
    // als Anteil des Außenradius angegeben.
    override func draw(_ rect: CGRect) {
        guard UIGraphicsGetCurrentContext() != nil, radius > 20 else { return }
        let c = dialCenter
        let r = radius
        let ringGray = Theme.rgb(0x494949)

        // Schwarze Außenkante, flacher grauer Ring, schwarzes Zifferblatt
        fillCircle(radius: r, color: .black)
        fillCircle(radius: r * 0.988, color: ringGray)
        fillCircle(radius: r * 0.886, color: .black)

        let speeds = speedValues()
        let scaleKmh = speeds.scale
        let fraction = CGFloat(max(0, min(1, speeds.current / scaleKmh)))
        let valueAngle = startAngle + sweep * fraction
        let white = isActive ? UIColor.white : Theme.textDark

        // Teilstriche: alle auf einer Mittellinie, drei Längen
        let layout = TachometerView.scaleLayout(scaleKmh)
        let tickMid = r * 0.794
        let labelFont = Theme.font(r * 0.148, bold: true)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: white]
        // Bis hierhin dürfen die Zahlen reichen, damit sie nicht an die langen Striche stoßen
        let labelLimit = tickMid - r * 0.115 / 2 - r * 0.03
        for i in 0...layout.ticks {
            let a = startAngle + sweep * CGFloat(i) / CGFloat(layout.ticks)
            let isEnd = i == 0 || i == layout.ticks
            let length: CGFloat
            let width: CGFloat
            if i % 4 == 0 || isEnd {
                length = r * 0.115; width = r * 0.031
            } else if i % 2 == 0 {
                length = r * 0.085; width = r * 0.024
            } else {
                length = r * 0.055; width = r * 0.024
            }
            let tick = UIBezierPath()
            tick.move(to: point(at: a, radius: tickMid - length / 2))
            tick.addLine(to: point(at: a, radius: tickMid + length / 2))
            tick.lineWidth = max(1.5, width)
            tick.lineCapStyle = .butt
            white.setStroke()
            tick.stroke()

            if i % layout.labelEvery == 0 || isEnd {
                let value = scaleKmh * Double(i) / Double(layout.ticks)
                let text = "\(Int(value.rounded()))" as NSString
                let size = text.size(withAttributes: labelAttrs)
                var tp = point(at: a, radius: r * 0.6)
                // 0 und Endwert stehen unten in einer Zeile mit der Geschwindigkeit,
                // schräg oben stehende Zahlen sitzen an der ECoS etwas höher
                if isEnd {
                    tp.y = c.y + r * 0.5
                } else if tp.y < c.y {
                    tp.y -= r * 0.065 * abs(cos(a))
                }
                // Lange Zahlen (100, 120 …) so weit zur Mitte rücken, dass die äußerste Ecke frei bleibt
                let hw = size.width / 2
                let hh = labelFont.capHeight / 2
                let dx = abs(tp.x - c.x)
                let dy = abs(tp.y - c.y)
                if hypot(dx + hw, dy + hh) > labelLimit {
                    if isEnd {
                        // in der Zeile der Geschwindigkeit bleiben, nur waagrecht einrücken
                        let x = sqrt(max(0, labelLimit * labelLimit - (dy + hh) * (dy + hh))) - hw
                        tp.x = c.x + (tp.x < c.x ? -x : x)
                    } else {
                        let qa = dx * dx + dy * dy
                        let qb = dx * hw + dy * hh
                        let qc = hw * hw + hh * hh - labelLimit * labelLimit
                        let k = max(0, (-qb + sqrt(max(0, qb * qb - qa * qc))) / qa)
                        tp = CGPoint(x: c.x + (tp.x - c.x) * k, y: c.y + (tp.y - c.y) * k)
                    }
                }
                text.draw(at: CGPoint(x: tp.x - size.width / 2, y: tp.y - size.height / 2), withAttributes: labelAttrs)
            }
        }

        // Geschwindigkeit rechtsbündig unter der Nabe, darunter km/h (bei Nothalt rot NOTHALT)
        let speedFont = Theme.font(r * 0.18, bold: true)
        let speedAttrs: [NSAttributedString.Key: Any] = [.font: speedFont, .foregroundColor: white]
        let speedText = "\(Int(speeds.current.rounded()))" as NSString
        let speedSize = speedText.size(withAttributes: speedAttrs)
        speedText.draw(at: CGPoint(x: c.x + r * 0.143 - speedSize.width, y: c.y + r * 0.5 - speedSize.height / 2),
                       withAttributes: speedAttrs)
        let unitAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(r * 0.13, bold: true),
                                                        .foregroundColor: emergencyStop ? Theme.red : white]
        let unit = (emergencyStop ? "NOTHALT" : "km/h") as NSString
        let unitSize = unit.size(withAttributes: unitAttrs)
        unit.draw(at: CGPoint(x: c.x + r * 0.045 - unitSize.width / 2, y: c.y + r * 0.7 - unitSize.height / 2),
                  withAttributes: unitAttrs)

        // Gelber Zeiger: gerader Schaft mit dunkler Mittellinie, spitz auslaufend
        let halfW = r * 0.047
        let shoulder = r * 0.49
        let tipR = r * 0.68
        // Punkt auf dem Zeiger: `along` vom Mittelpunkt aus, `side` quer dazu
        func needlePoint(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
            return CGPoint(x: c.x + cos(valueAngle) * along - sin(valueAngle) * side,
                           y: c.y + sin(valueAngle) * along + cos(valueAngle) * side)
        }
        let needle = UIBezierPath()
        needle.move(to: needlePoint(0, halfW))
        needle.addLine(to: needlePoint(shoulder, halfW))
        needle.addLine(to: needlePoint(tipR, 0))
        needle.addLine(to: needlePoint(shoulder, -halfW))
        needle.addLine(to: needlePoint(0, -halfW))
        needle.close()
        let needleColor = isActive ? (emergencyStop ? Theme.red : Theme.rgb(0xFFDC00)) : Theme.textDark
        needleColor.setFill()
        needle.fill()
        let midLine = UIBezierPath()
        midLine.move(to: point(at: valueAngle, radius: r * 0.12))
        midLine.addLine(to: point(at: valueAngle, radius: shoulder * 0.97))
        midLine.lineWidth = max(1, r * 0.016)
        Theme.rgb(0x504A10).setStroke()
        midLine.stroke()

        // Flache graue Nabe
        fillCircle(radius: r * 0.138, color: ringGray)
    }
}
