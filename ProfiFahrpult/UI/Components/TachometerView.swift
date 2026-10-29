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

        // Matter, dunkelgrauer Gehäusering wie an der ECoS, oben leicht aufgehellt
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.clip()
        let ring = [Theme.rgb(0x6B6E74).cgColor, Theme.rgb(0x3A3C41).cgColor, Theme.rgb(0x26282C).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: ring, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y + r), options: [])
        }
        ctx.restoreGState()

        // Schwarzes Zifferblatt mit feiner Innenkante
        let faceR = r * 0.88
        let face = UIBezierPath(ovalIn: CGRect(x: c.x - faceR, y: c.y - faceR, width: 2 * faceR, height: 2 * faceR))
        UIColor(white: 0.03, alpha: 1).setFill()
        face.fill()
        face.lineWidth = max(1, r * 0.012)
        UIColor(white: 0.0, alpha: 1).setStroke()
        face.stroke()

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
        // Wie an der ECoS trägt nur jeder zweite Hauptstrich eine Zahl (0, 40, 80, 120 …);
        // der Endwert wird immer beschriftet, liegt er dicht an einer Zahl, entfällt diese
        let labeled = values.filter { Int($0.rounded()) % (interval * 2) == 0 && $0 < scaleKmh - 0.001 }
        let lastLabeled = labeled.last ?? 0
        let skipLabel = scaleKmh - lastLabeled < Double(interval) * 0.9 ? lastLabeled : -1
        let outer = faceR * 0.92
        for mark in values {
            let a = startAngle + sweep * CGFloat(mark / scaleKmh)
            let isEnd = abs(mark - scaleKmh) < 0.001
            let isMajor = Int(mark.rounded()) % interval == 0 || isEnd
            let isLabeled = isEnd || (Int(mark.rounded()) % (interval * 2) == 0 && mark != skipLabel)
            let inner = outer - (isMajor ? r * 0.13 : r * 0.07)
            let tick = UIBezierPath()
            tick.move(to: point(at: a, radius: inner))
            tick.addLine(to: point(at: a, radius: outer))
            tick.lineWidth = max(2.5, r * (isMajor ? 0.045 : 0.03))
            tick.lineCapStyle = .butt
            white.setStroke()
            tick.stroke()
            if isLabeled {
                let text = "\(Int(mark.rounded()))" as NSString
                let size = text.size(withAttributes: numberAttrs)
                let tp = point(at: a, radius: inner - fontSize * 1.15)
                text.draw(at: CGPoint(x: tp.x - size.width / 2, y: tp.y - size.height / 2), withAttributes: numberAttrs)
            }
        }

        // Unten im freien Bereich, den der Zeiger nie überstreicht: Geschwindigkeit, km/h,
        // darunter Fahrstufe und Adresse (wie "FS 28 [0243]" an der ECoS)
        let kmhAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(r * 0.2, bold: true),
                                                       .foregroundColor: white]
        let kmh = "\(Int(speeds.current.rounded()))" as NSString
        let kmhSize = kmh.size(withAttributes: kmhAttrs)
        let kmhY = c.y + r * 0.34
        kmh.draw(at: CGPoint(x: c.x - kmhSize.width / 2, y: kmhY), withAttributes: kmhAttrs)
        let unitAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(max(8, r * 0.075), bold: true),
                                                        .foregroundColor: white]
        let unit = "km/h" as NSString
        let unitSize = unit.size(withAttributes: unitAttrs)
        let unitY = kmhY + kmhSize.height - r * 0.03
        unit.draw(at: CGPoint(x: c.x - unitSize.width / 2, y: unitY), withAttributes: unitAttrs)

        let infoAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(max(8, r * 0.065), bold: true),
                                                        .foregroundColor: emergencyStop ? Theme.red : Theme.rgb(0xA8ABB2)]
        var info = emergencyStop ? "NOTHALT" : "FS \(step)"
        if let address = addressText {
            info += " " + address
        }
        let infoText = info as NSString
        let infoSize = infoText.size(withAttributes: infoAttrs)
        infoText.draw(at: CGPoint(x: c.x - infoSize.width / 2, y: unitY + unitSize.height + r * 0.01), withAttributes: infoAttrs)

        // Gelber Zeiger wie an der ECoS: breiter Fuß an der Nabe, spitz auslaufend, dunkle Kante
        let needleLen = outer - r * 0.16
        let baseW = r * 0.075
        let tip = point(at: valueAngle, radius: needleLen)
        let left = point(at: valueAngle + .pi / 2, radius: baseW)
        let right = point(at: valueAngle - .pi / 2, radius: baseW)
        let tailL = point(at: valueAngle + .pi * 0.82, radius: baseW * 1.1)
        let tailR = point(at: valueAngle - .pi * 0.82, radius: baseW * 1.1)
        let needle = UIBezierPath()
        needle.move(to: tip)
        needle.addLine(to: left)
        needle.addLine(to: tailL)
        needle.addLine(to: tailR)
        needle.addLine(to: right)
        needle.close()
        needle.lineJoinStyle = .round
        let needleColor = isActive ? (emergencyStop ? Theme.red : Theme.functionOn) : Theme.textDark
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.cgColor)
        needleColor.setFill()
        needle.fill()
        ctx.restoreGState()
        needle.lineWidth = max(1, r * 0.012)
        needleColor.withBrightnessFactor(0.55).setStroke()
        needle.stroke()

        // Graue Nabe mit dunklem Rand
        let hubR = r * 0.11
        let hub = UIBezierPath(ovalIn: CGRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2))
        ctx.saveGState()
        hub.addClip()
        let hubColors = [Theme.rgb(0x6E7177).cgColor, Theme.rgb(0x35373C).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: hubColors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y - hubR), end: CGPoint(x: c.x, y: c.y + hubR), options: [])
        }
        ctx.restoreGState()
        hub.lineWidth = max(1, r * 0.015)
        Theme.rgb(0x1A1B1E).setStroke()
        hub.stroke()
    }
}
