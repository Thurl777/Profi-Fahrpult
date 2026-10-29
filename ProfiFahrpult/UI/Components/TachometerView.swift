import UIKit

/// Rundinstrument wie der Tacho der ECoS: schwarzes Zifferblatt mit dunkelblauem Ring,
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
    /// Lokadresse neben der Nabe, z.B. "[0218]"
    var addressText: String? { didSet { setNeedsDisplay() } }
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
    private var radius: CGFloat { return min(bounds.width, bounds.height) / 2 - 2 }

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

    private func scaleInterval(_ scaleKmh: Double) -> Int {
        if scaleKmh <= 60 { return 10 }
        if scaleKmh <= 160 { return 20 }
        if scaleKmh <= 400 { return 50 }
        return 100
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

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), radius > 20 else { return }
        let c = dialCenter
        let r = radius
        let space = CGColorSpaceCreateDeviceRGB()

        // Dunkelblauer Ring
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.clip()
        let ring = [Theme.rgb(0x525A86).cgColor, Theme.rgb(0x2E3456).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: ring, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y + r), options: [])
        }
        ctx.restoreGState()

        // Schwarzes Zifferblatt
        let faceR = r * 0.9
        UIColor(white: 0.04, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - faceR, y: c.y - faceR, width: 2 * faceR, height: 2 * faceR)).fill()

        let speeds = speedValues()
        let scaleKmh = speeds.scale
        let fraction = CGFloat(max(0, min(1, speeds.current / scaleKmh)))
        let valueAngle = startAngle + sweep * fraction
        let white = isActive ? UIColor.white : Theme.textDark

        // Teilstriche: kräftige weiße Balken mit runden Enden
        let interval = scaleInterval(scaleKmh)
        let fontSize = max(10, r * 0.12)
        let numberAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(fontSize, bold: true),
                                                          .foregroundColor: white]
        var values: [Double] = []
        var v = 0.0
        while v <= scaleKmh + 0.001 {
            values.append(v)
            v += Double(interval) / 2
        }
        if let last = values.last, last < scaleKmh - 0.001 {
            values.append(scaleKmh)
        }
        // Der Endwert wird immer beschriftet; liegt er dicht am letzten Hauptstrich, entfällt dessen Zahl
        let lastMajor = values.last(where: { Int($0) % interval == 0 && $0 < scaleKmh - 0.001 }) ?? 0
        let skipLabel = scaleKmh - lastMajor < Double(interval) * 0.45 ? lastMajor : -1
        let outer = faceR * 0.9
        for mark in values {
            let a = startAngle + sweep * CGFloat(mark / scaleKmh)
            let isEnd = abs(mark - scaleKmh) < 0.001
            let isMajor = Int(mark) % interval == 0 || isEnd
            let inner = outer - (isMajor ? r * 0.12 : r * 0.07)
            let tick = UIBezierPath()
            tick.move(to: point(at: a, radius: inner))
            tick.addLine(to: point(at: a, radius: outer))
            tick.lineWidth = max(2.5, r * (isMajor ? 0.04 : 0.03))
            tick.lineCapStyle = .round
            white.setStroke()
            tick.stroke()
            if isMajor && mark != skipLabel {
                let text = "\(Int(mark.rounded()))" as NSString
                let size = text.size(withAttributes: numberAttrs)
                let tp = point(at: a, radius: inner - fontSize * 1.15)
                text.draw(at: CGPoint(x: tp.x - size.width / 2, y: tp.y - size.height / 2), withAttributes: numberAttrs)
            }
        }

        // Fahrstufe und Adresse unter der Nabe (wie "M28 [0243]" an der ECoS)
        let infoAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(max(9, r * 0.1), bold: true),
                                                        .foregroundColor: emergencyStop ? Theme.red : white]
        var info = emergencyStop ? "NOTHALT" : "FS \(step)"
        if let address = addressText {
            info += " " + address
        }
        let infoText = info as NSString
        let infoSize = infoText.size(withAttributes: infoAttrs)
        infoText.draw(at: CGPoint(x: c.x - infoSize.width / 2, y: c.y + r * 0.2), withAttributes: infoAttrs)

        // Geschwindigkeit unten in der Mitte
        let kmhAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(r * 0.17, bold: true),
                                                       .foregroundColor: white]
        let kmh = "\(Int(speeds.current.rounded()))" as NSString
        let kmhSize = kmh.size(withAttributes: kmhAttrs)
        kmh.draw(at: CGPoint(x: c.x - kmhSize.width / 2, y: c.y + r * 0.5), withAttributes: kmhAttrs)
        let unitAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(max(8, r * 0.07), bold: true),
                                                        .foregroundColor: Theme.textDark]
        let unit = "km/h" as NSString
        let unitSize = unit.size(withAttributes: unitAttrs)
        unit.draw(at: CGPoint(x: c.x - unitSize.width / 2, y: c.y + r * 0.5 + kmhSize.height - 3), withAttributes: unitAttrs)

        // Gelber Zeiger: breiter Balken, der zur Spitze schmaler wird
        let needleLen = outer - r * 0.02
        let tip = point(at: valueAngle, radius: needleLen)
        let tipL = point(at: valueAngle + 0.012, radius: needleLen)
        let tipR = point(at: valueAngle - 0.012, radius: needleLen)
        let baseW = r * 0.045
        let left = point(at: valueAngle + .pi / 2, radius: baseW)
        let right = point(at: valueAngle - .pi / 2, radius: baseW)
        let needle = UIBezierPath()
        needle.move(to: left)
        needle.addLine(to: tipL)
        needle.addLine(to: tip)
        needle.addLine(to: tipR)
        needle.addLine(to: right)
        needle.close()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.cgColor)
        (isActive ? (emergencyStop ? Theme.red : Theme.functionOn) : Theme.textDark).setFill()
        needle.fill()
        ctx.restoreGState()

        // Dunkelblaue Nabe
        let hubR = r * 0.12
        Theme.rgb(0x3A4468).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2)).fill()
    }
}
