import UIKit

/// Rundinstrument wie der Tacho der ECoS: schwarzes Zifferblatt mit grauem Ring,
/// weißen Teilstrichen und gelbem Zeiger.
///
/// Zwei Betriebsarten:
/// - Drehregler (`smoothNeedle = false`): eine kreisende Bewegung auf dem Instrument ändert die
///   Fahrstufe relativ, der Zeiger springt von Fahrstufe zu Fahrstufe.
/// - Anzeige (`smoothNeedle = true`): der Zeiger gleitet mit `needleDelay` gleichmäßig zur Fahrstufe
///   und lässt sich nicht per Touch drehen. Eingestellt wird am Schieberegler oder an der Multimaus.
final class TachometerView: UIControl {

    var maxStep: Int = 126 {
        didSet {
            step = min(step, maxStep)
            updateNeedleTarget()
        }
    }

    var step: Int = 0 {
        didSet {
            if oldValue != step {
                accumulated = Double(step)
                updateNeedleTarget()
            }
        }
    }

    /// km/h bei höchster Fahrstufe, solange keine Kennlinie gesetzt ist
    var maxSpeedKmh: Int = 120 { didSet { setNeedsDisplay() } }
    /// Eingemessene Kennlinie der Lok. Zeiger und Anzeige folgen dann der Maßstabsgeschwindigkeit.
    var speedCurve: SpeedCurve? { didSet { setNeedsDisplay() } }
    var forward: Bool = true { didSet { setNeedsDisplay() } }
    var emergencyStop: Bool = false {
        didSet {
            // Bei Nothalt steht die Lok sofort, der Zeiger fällt ohne Gleiten zurück
            if emergencyStop && !oldValue { snapNeedle() }
            setNeedsDisplay()
        }
    }
    /// Schaltet das Instrument bei fehlender Lok/Verbindung grau
    var isActive: Bool = true { didSet { setNeedsDisplay() } }

    /// Zeiger gleitet gleichmäßig zur Fahrstufe, keine Bedienung per Touch
    var smoothNeedle: Bool = false {
        didSet {
            guard oldValue != smoothNeedle else { return }
            if !smoothNeedle { snapNeedle() }
        }
    }
    /// Ungefähre Zeit in Sekunden, bis der gleitende Zeiger die neue Fahrstufe erreicht
    var needleDelay: Double {
        get { return damper.delay }
        set { damper.delay = newValue }
    }

    private let startAngle = CGFloat.pi * 0.75
    private let sweep = CGFloat.pi * 1.5
    private var lastAngle: CGFloat = 0
    private var accumulated: Double = 0

    /// Angezeigte Zeigerstellung als Anteil der höchsten Fahrstufe (0…1)
    private var damper = NeedleDamper(value: 0, delay: AppSettings.defaultTachoDelay)
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0

    /// Zifferblatt ohne Zeiger, wird nur bei Änderung von Größe, Skala oder Farbe neu gezeichnet
    private var dialImage: UIImage?
    private var dialImageKey: DialKey?

    private struct DialKey: Equatable {
        let size: CGSize
        let scaleKmh: Double
        let isActive: Bool
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        displayLink?.invalidate()
    }

    private var dialCenter: CGPoint { return CGPoint(x: bounds.midX, y: bounds.midY) }
    private var radius: CGFloat { return min(bounds.width, bounds.height) / 2 - 1 }

    // MARK: Zeigerbewegung

    private var targetFraction: Double {
        return maxStep > 0 ? Double(max(0, min(step, maxStep))) / Double(maxStep) : 0
    }

    /// Zeiger ohne Gleiten auf die aktuelle Fahrstufe stellen (z.B. beim Lokwechsel)
    func snapNeedle() {
        damper.jump(to: targetFraction)
        stopDisplayLink()
        setNeedsDisplay()
    }

    private func updateNeedleTarget() {
        guard smoothNeedle else {
            snapNeedle()
            return
        }
        damper.target = targetFraction
        if damper.isSettled {
            stopDisplayLink()
        } else {
            startDisplayLink()
        }
        setNeedsDisplay()
    }

    private func startDisplayLink() {
        guard displayLink == nil, window != nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        lastFrameTime = 0
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func displayLinkFired(_ link: CADisplayLink) {
        let dt = lastFrameTime > 0 ? link.timestamp - lastFrameTime : link.duration
        lastFrameTime = link.timestamp
        damper.advance(by: min(max(dt, 0), 0.1))
        if damper.isSettled { stopDisplayLink() }
        setNeedsDisplay()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else if !damper.isSettled {
            startDisplayLink()
        }
    }

    // MARK: Bedienung

    private func angle(of point: CGPoint) -> CGFloat {
        return atan2(point.y - dialCenter.y, point.x - dialCenter.x)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled, !smoothNeedle else { return false }
        let p = touch.location(in: self)
        let dist = hypot(p.x - dialCenter.x, p.y - dialCenter.y)
        guard dist <= radius * 1.05 else { return false }
        lastAngle = angle(of: p)
        accumulated = Double(step)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        // Während einer Drehung auf Anzeige umgeschaltet: Bedienung beenden
        guard !smoothNeedle else { return false }
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

    /// Endwert der Skala und angezeigte Geschwindigkeit in km/h
    private func speedValues() -> (scale: Double, current: Double) {
        let stepFraction = max(0, min(1, damper.value))
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

        let speeds = speedValues()
        let scaleKmh = speeds.scale
        let fraction = CGFloat(max(0, min(1, speeds.current / scaleKmh)))
        let valueAngle = startAngle + sweep * fraction
        let white = isActive ? UIColor.white : Theme.textDark

        // Zifferblatt aus dem Zwischenspeicher, damit der gleitende Zeiger flüssig läuft
        let key = DialKey(size: bounds.size, scaleKmh: scaleKmh, isActive: isActive)
        if dialImage == nil || dialImageKey != key {
            dialImage = UIGraphicsImageRenderer(bounds: bounds).image { _ in
                drawDial(scaleKmh: scaleKmh, white: white)
            }
            dialImageKey = key
        }
        dialImage?.draw(in: bounds)

        // Geschwindigkeit mittig unter der Nabe, darunter km/h (bei Nothalt rot NOTHALT)
        let speedFont = Theme.font(r * 0.18, bold: true)
        let speedAttrs: [NSAttributedString.Key: Any] = [.font: speedFont, .foregroundColor: white]
        let speedText = "\(Int(speeds.current.rounded()))" as NSString
        let speedSize = speedText.size(withAttributes: speedAttrs)
        speedText.draw(at: CGPoint(x: c.x - speedSize.width / 2, y: c.y + r * 0.5 - speedSize.height / 2),
                       withAttributes: speedAttrs)
        let unitAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(r * 0.13, bold: true),
                                                        .foregroundColor: emergencyStop ? Theme.red : white]
        let unit = (emergencyStop ? "NOTHALT" : "km/h") as NSString
        let unitSize = unit.size(withAttributes: unitAttrs)
        unit.draw(at: CGPoint(x: c.x - unitSize.width / 2, y: c.y + r * 0.7 - unitSize.height / 2),
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

    /// Ring, Teilstriche und Zahlen
    private func drawDial(scaleKmh: Double, white: UIColor) {
        let c = dialCenter
        let r = radius

        // Schwarze Außenkante, flacher grauer Ring, schwarzes Zifferblatt
        fillCircle(radius: r, color: .black)
        fillCircle(radius: r * 0.988, color: Theme.rgb(0x494949))
        fillCircle(radius: r * 0.886, color: .black)

        // Teilstriche: alle auf einer Mittellinie, drei Längen
        let layout = TachometerView.scaleLayout(scaleKmh)
        let tickMid = r * 0.794
        var ticks: [(angle: CGFloat, inner: CGFloat, outer: CGFloat, width: CGFloat)] = []
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
            ticks.append((a, tickMid - length / 2, tickMid + length / 2, max(1.5, width)))
        }

        // Kleinster Abstand zwischen einer Zahl (Ziffernhöhe, ohne Ober-/Unterlänge) und den Strichen
        func clearance(_ center: CGPoint, halfWidth hw: CGFloat, halfHeight hh: CGFloat) -> CGFloat {
            var best = CGFloat.greatestFiniteMagnitude
            for t in ticks {
                for k in 0...8 {
                    let p = point(at: t.angle, radius: t.inner + (t.outer - t.inner) * CGFloat(k) / 8)
                    let dx = max(abs(p.x - center.x) - hw, 0)
                    let dy = max(abs(p.y - center.y) - hh, 0)
                    best = min(best, hypot(dx, dy) - t.width / 2)
                }
            }
            return best
        }

        let labelFont = Theme.font(r * 0.148, bold: true)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: white]
        let minGap = r * 0.012
        for i in 0...layout.ticks where i % layout.labelEvery == 0 || i == layout.ticks {
            let a = ticks[i].angle
            let isEnd = i == 0 || i == layout.ticks
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
            // Stößt eine Zahl (z.B. dreistellig) an einen Strich, rückt sie nur so weit zur Mitte wie nötig;
            // die Endwerte bleiben dabei in ihrer Zeile
            let hw = size.width / 2
            let hh = labelFont.capHeight / 2
            let stepLen = max(0.5, r * 0.002)
            var tries = 0
            while clearance(tp, halfWidth: hw, halfHeight: hh) < minGap && tries < 100 {
                if isEnd {
                    tp.x += tp.x > c.x ? -stepLen : stepLen
                } else {
                    let d = max(1, hypot(tp.x - c.x, tp.y - c.y))
                    tp.x -= (tp.x - c.x) / d * stepLen
                    tp.y -= (tp.y - c.y) / d * stepLen
                }
                tries += 1
            }
            text.draw(at: CGPoint(x: tp.x - size.width / 2, y: tp.y - size.height / 2), withAttributes: labelAttrs)
        }
    }
}

/// CADisplayLink hält sein Ziel fest; der Umweg verhindert, dass der Tacho nie freigegeben wird
private final class DisplayLinkProxy: NSObject {
    private weak var tacho: TachometerView?

    init(_ tacho: TachometerView) {
        self.tacho = tacho
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let tacho = tacho else {
            link.invalidate()
            return
        }
        tacho.displayLinkFired(link)
    }
}
