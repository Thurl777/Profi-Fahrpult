import UIKit

/// Rundinstrument im Stil des ECoS-Fahrreglers. Wird wie ein Drehknopf bedient:
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

        // Chromring
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.clip()
        let ring = [Theme.rgb(0x9A9FA6).cgColor, Theme.rgb(0x2B2E33).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: ring, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y - r), end: CGPoint(x: c.x, y: c.y + r), options: [])
        }
        ctx.restoreGState()

        // Zifferblatt
        let faceR = r * 0.94
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - faceR, y: c.y - faceR, width: 2 * faceR, height: 2 * faceR))
        ctx.clip()
        let face = [Theme.rgb(0x2A2F37).cgColor, Theme.rgb(0x07080A).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: face, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x, y: c.y - faceR * 0.3), startRadius: 0,
                                   endCenter: c, endRadius: faceR, options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()

        let speeds = speedValues()
        let scaleKmh = speeds.scale
        let fraction = CGFloat(max(0, min(1, speeds.current / scaleKmh)))
        let valueAngle = startAngle + sweep * fraction
        let activeColor = isActive ? (emergencyStop ? Theme.red : Theme.accent) : Theme.textDark

        // Skalenbogen (Hintergrund + Wert)
        let arcR = faceR * 0.86
        let arcWidth = max(6, r * 0.07)
        let track = UIBezierPath(arcCenter: c, radius: arcR, startAngle: startAngle,
                                 endAngle: startAngle + sweep, clockwise: true)
        track.lineWidth = arcWidth
        track.lineCapStyle = .butt
        Theme.rgb(0x1E2228).setStroke()
        track.stroke()
        if fraction > 0 {
            let value = UIBezierPath(arcCenter: c, radius: arcR, startAngle: startAngle,
                                     endAngle: valueAngle, clockwise: true)
            value.lineWidth = arcWidth
            value.lineCapStyle = .butt
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: activeColor.cgColor)
            activeColor.setStroke()
            value.stroke()
            ctx.restoreGState()
        }

        // Teilstriche und Zahlen
        let interval = scaleInterval(scaleKmh)
        let fontSize = max(9, r * 0.09)
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(fontSize, bold: true),
                                                    .foregroundColor: Theme.textDim]
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
        for mark in values {
            let a = startAngle + sweep * CGFloat(mark / scaleKmh)
            let isEnd = abs(mark - scaleKmh) < 0.001
            let isMajor = Int(mark) % interval == 0 || isEnd
            let outer = arcR - arcWidth / 2 - 3
            let inner = outer - (isMajor ? r * 0.08 : r * 0.04)
            let tick = UIBezierPath()
            tick.move(to: point(at: a, radius: inner))
            tick.addLine(to: point(at: a, radius: outer))
            tick.lineWidth = isMajor ? 2 : 1
            (isMajor ? UIColor.white : Theme.textDim).setStroke()
            tick.stroke()
            if isMajor && mark != skipLabel {
                let text = "\(Int(mark.rounded()))" as NSString
                let size = text.size(withAttributes: attrs)
                let tp = point(at: a, radius: inner - fontSize * 1.1)
                text.draw(at: CGPoint(x: tp.x - size.width / 2, y: tp.y - size.height / 2), withAttributes: attrs)
            }
        }

        // Digitalanzeige
        let kmh = Int(speeds.current.rounded())
        let bigAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(r * 0.24, bold: true),
                                                       .foregroundColor: isActive ? UIColor.white : Theme.textDark]
        let big = "\(kmh)" as NSString
        let bigSize = big.size(withAttributes: bigAttrs)
        big.draw(at: CGPoint(x: c.x - bigSize.width / 2, y: c.y + r * 0.22), withAttributes: bigAttrs)

        let smallAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(r * 0.075, bold: true),
                                                         .foregroundColor: Theme.textDim]
        let unit = "km/h" as NSString
        let unitSize = unit.size(withAttributes: smallAttrs)
        unit.draw(at: CGPoint(x: c.x - unitSize.width / 2, y: c.y + r * 0.22 + bigSize.height - 2), withAttributes: smallAttrs)

        let stepText = (emergencyStop ? "NOTHALT" : "FS \(step)/\(maxStep)") as NSString
        let stepAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(r * 0.08, bold: true),
                                                        .foregroundColor: emergencyStop ? Theme.red : Theme.accent]
        let stepSize = stepText.size(withAttributes: stepAttrs)
        stepText.draw(at: CGPoint(x: c.x - stepSize.width / 2, y: c.y - r * 0.42), withAttributes: stepAttrs)

        // Richtungspfeil
        let arrowW = r * 0.16
        let arrowY = c.y - r * 0.2
        let arrow = UIBezierPath()
        if forward {
            arrow.move(to: CGPoint(x: c.x + arrowW, y: arrowY))
            arrow.addLine(to: CGPoint(x: c.x - arrowW * 0.4, y: arrowY - arrowW * 0.6))
            arrow.addLine(to: CGPoint(x: c.x - arrowW * 0.4, y: arrowY + arrowW * 0.6))
        } else {
            arrow.move(to: CGPoint(x: c.x - arrowW, y: arrowY))
            arrow.addLine(to: CGPoint(x: c.x + arrowW * 0.4, y: arrowY - arrowW * 0.6))
            arrow.addLine(to: CGPoint(x: c.x + arrowW * 0.4, y: arrowY + arrowW * 0.6))
        }
        arrow.close()
        (isActive ? Theme.functionOn : Theme.textDark).setFill()
        arrow.fill()

        // Zeiger
        let needleLen = arcR - arcWidth
        let tip = point(at: valueAngle, radius: needleLen)
        let baseW = r * 0.035
        let left = point(at: valueAngle + .pi / 2, radius: baseW)
        let right = point(at: valueAngle - .pi / 2, radius: baseW)
        let tail = point(at: valueAngle + .pi, radius: r * 0.12)
        let needle = UIBezierPath()
        needle.move(to: tip)
        needle.addLine(to: left)
        needle.addLine(to: tail)
        needle.addLine(to: right)
        needle.close()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.cgColor)
        (isActive ? Theme.rgb(0xFF5A1F) : Theme.textDark).setFill()
        needle.fill()
        ctx.restoreGState()

        // Nabe
        let hubR = r * 0.075
        let hub = UIBezierPath(ovalIn: CGRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2))
        ctx.saveGState()
        hub.addClip()
        let hubColors = [Theme.rgb(0xC8CDD4).cgColor, Theme.rgb(0x3B3F45).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: hubColors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x, y: c.y - hubR), end: CGPoint(x: c.x, y: c.y + hubR), options: [])
        }
        ctx.restoreGState()
    }
}
