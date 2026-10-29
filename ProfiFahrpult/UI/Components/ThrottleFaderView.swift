import UIKit

/// Senkrechter Schieberegler neben dem Tacho, gestaltet wie der Fahrregler eines Handreglers:
/// dunkler Schlitz, Strichskala mit Fahrstufen an der Seite, gerippter Griff mit gelber Marke.
/// Bedient dieselbe Fahrstufe wie der Tacho und lässt sich in den Einstellungen ausblenden.
final class ThrottleFaderView: UIControl {

    enum ScaleSide {
        case left
        case right
    }

    /// Seite des Schlitzes, auf der die Skala steht (zum Tacho hin)
    var scaleSide: ScaleSide = .right { didSet { setNeedsDisplay() } }

    var maxStep: Int = 126 {
        didSet {
            step = min(step, maxStep)
            setNeedsDisplay()
        }
    }

    var step: Int = 0 {
        didSet {
            if oldValue != step { setNeedsDisplay() }
        }
    }

    var isActive: Bool = true { didSet { setNeedsDisplay() } }

    private let knobWidth: CGFloat = 30
    private let knobHeight: CGFloat = 40
    private let slotWidth: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: Geometrie

    /// Mitte des Schlitzes: an der Außenkante, die Skala liegt innen
    private var slotX: CGFloat {
        return scaleSide == .right ? knobWidth / 2 + 2 : bounds.width - knobWidth / 2 - 2
    }

    /// Bereich, in dem sich die Mitte des Griffs bewegt
    private var travel: (top: CGFloat, bottom: CGFloat) {
        return (knobHeight / 2 + 4, bounds.height - knobHeight / 2 - 4)
    }

    private func y(forStep s: Int) -> CGFloat {
        let t = travel
        guard maxStep > 0 else { return t.bottom }
        return t.bottom - (t.bottom - t.top) * CGFloat(s) / CGFloat(maxStep)
    }

    private func stepValue(forY y: CGFloat) -> Int {
        let t = travel
        guard t.bottom > t.top else { return 0 }
        let fraction = (t.bottom - y) / (t.bottom - t.top)
        return max(0, min(maxStep, Int((fraction * CGFloat(maxStep)).rounded())))
    }

    // MARK: Bedienung

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        updateStep(from: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateStep(from: touch)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        sendActions(for: .editingDidEnd)
    }

    private func updateStep(from touch: UITouch) {
        let newStep = stepValue(forY: touch.location(in: self).y)
        if newStep != step {
            step = newStep
            sendActions(for: .valueChanged)
        }
    }

    // MARK: Zeichnen

    override func draw(_ rect: CGRect) {
        let t = travel
        let slot = CGRect(x: slotX - slotWidth / 2, y: t.top - 6, width: slotWidth, height: t.bottom - t.top + 12)
        let slotPath = UIBezierPath(roundedRect: slot, cornerRadius: slotWidth / 2)
        Theme.rgb(0x1C1D20).setFill()
        slotPath.fill()
        Theme.rgb(0x6A6D73).setStroke()
        slotPath.lineWidth = 1
        slotPath.stroke()

        drawScale()
        drawKnob(centerY: y(forStep: step))
    }

    /// Strichskala wie am Handregler: lange Striche mit Zahl, dazwischen kurze
    private func drawScale() {
        let major: Int
        switch maxStep {
        case ...14: major = 2
        case ...28: major = 4
        default: major = 20
        }
        let minor = max(1, major / 2)
        let toRight = scaleSide == .right
        let x0 = toRight ? slotX + knobWidth / 2 + 3 : slotX - knobWidth / 2 - 3
        let dir: CGFloat = toRight ? 1 : -1
        let color = isActive ? Theme.text : Theme.textDark
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(10, bold: true), .foregroundColor: color]
        var s = 0
        while s <= maxStep {
            let isMajor = s % major == 0 || s == maxStep
            // Liegt die höchste Fahrstufe dicht am letzten Hauptstrich, bleibt sie ohne Zahl
            let isLabeled = s % major == 0 || (s == maxStep && maxStep % major >= major / 2)
            let ty = y(forStep: s)
            let len: CGFloat = isMajor ? 9 : 5
            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: x0, y: ty))
            tick.addLine(to: CGPoint(x: x0 + dir * len, y: ty))
            tick.lineWidth = isMajor ? 2 : 1
            color.setStroke()
            tick.stroke()
            if isLabeled {
                let text = "\(s)" as NSString
                let size = text.size(withAttributes: attrs)
                // dreistellige Fahrstufen dürfen nicht über den Rand hinausragen
                let tx = min(max(0, toRight ? x0 + len + 3 : x0 - len - 3 - size.width), bounds.width - size.width)
                text.draw(at: CGPoint(x: tx, y: ty - size.height / 2), withAttributes: attrs)
            }
            s += s + minor > maxStep && s < maxStep ? maxStep - s : minor
        }
    }

    private func drawKnob(centerY: CGFloat) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let rect = CGRect(x: slotX - knobWidth / 2, y: centerY - knobHeight / 2, width: knobWidth, height: knobHeight)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        Theme.rgb(0x2B2D31).setFill()
        path.fill()
        ctx.restoreGState()

        ctx.saveGState()
        path.addClip()
        let colors = [Theme.rgb(0x6A6D73).cgColor, Theme.rgb(0x2B2D31).cgColor, Theme.rgb(0x1A1B1E).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
        // Griffrippen
        let ribs = UIBezierPath()
        for dy: CGFloat in [-13, -9, -5, 5, 9, 13] {
            ribs.move(to: CGPoint(x: rect.minX + 4, y: rect.midY + dy))
            ribs.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY + dy))
        }
        ribs.lineWidth = 1.5
        UIColor.black.withAlphaComponent(0.55).setStroke()
        ribs.stroke()
        ctx.restoreGState()

        path.lineWidth = 1
        Theme.rgb(0x111214).setStroke()
        path.stroke()

        // Gelbe Ablesemarke
        let mark = UIBezierPath(rect: CGRect(x: rect.minX + 2, y: rect.midY - 1.5, width: rect.width - 4, height: 3))
        (isActive ? Theme.functionOn : Theme.textDark).setFill()
        mark.fill()
    }
}
