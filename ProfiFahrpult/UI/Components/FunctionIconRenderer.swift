import UIKit

/// Zeichnet die Funktionssymbole als Vektorgrafik (keine SF Symbols, damit auch iOS < 13 unterstützt wird).
enum FunctionIconRenderer {

    private static var cache: [String: UIImage] = [:]

    static func image(_ icon: FunctionIcon, size: CGFloat, color: UIColor) -> UIImage? {
        if icon == .generic { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(icon.rawValue)-\(Int(size))-\(Int(r * 255))-\(Int(g * 255))-\(Int(b * 255))"
        if let img = cache[key] { return img }

        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        defer { UIGraphicsEndImageContext() }
        color.setStroke()
        color.setFill()
        draw(icon, s: size)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        if let img = img { cache[key] = img }
        return img
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func draw(_ icon: FunctionIcon, s: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { return CGPoint(x: x * s, y: y * s) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            return CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
        }
        func line(_ pts: [CGPoint], width: CGFloat = 0.07) {
            let path = UIBezierPath()
            path.lineWidth = width * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            guard let first = pts.first else { return }
            path.move(to: first)
            for q in pts.dropFirst() { path.addLine(to: q) }
            path.stroke()
        }
        func headlight(mirrored: Bool, beams: [CGFloat], long: Bool) {
            let lamp = UIBezierPath()
            let x0: CGFloat = mirrored ? 0.62 : 0.38
            lamp.move(to: p(x0, 0.22))
            if mirrored {
                lamp.addArc(withCenter: p(x0, 0.5), radius: 0.28 * s, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
            } else {
                lamp.addArc(withCenter: p(x0, 0.5), radius: 0.28 * s, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            }
            lamp.close()
            lamp.fill()
            let start: CGFloat = mirrored ? 0.30 : 0.70
            let end: CGFloat = mirrored ? (long ? 0.02 : 0.10) : (long ? 0.98 : 0.90)
            for y in beams {
                line([p(start + (mirrored ? -0.04 : 0.04), y), p(end, y + (long ? 0 : (y - 0.5) * 0.25))])
            }
        }
        func speaker() {
            let path = UIBezierPath()
            path.move(to: p(0.12, 0.38))
            path.addLine(to: p(0.28, 0.38))
            path.addLine(to: p(0.48, 0.2))
            path.addLine(to: p(0.48, 0.8))
            path.addLine(to: p(0.28, 0.62))
            path.addLine(to: p(0.12, 0.62))
            path.close()
            path.fill()
        }

        switch icon {
        case .generic:
            break

        case .light:
            headlight(mirrored: false, beams: [0.3, 0.5, 0.7], long: false)

        case .lightRear:
            headlight(mirrored: true, beams: [0.3, 0.5, 0.7], long: false)

        case .highBeam:
            headlight(mirrored: false, beams: [0.28, 0.42, 0.58, 0.72], long: true)

        case .cabLight:
            // Führerhaus mit Lampe
            line([p(0.15, 0.85), p(0.15, 0.35), p(0.5, 0.15), p(0.85, 0.35), p(0.85, 0.85), p(0.15, 0.85)], width: 0.06)
            UIBezierPath(ovalIn: rect(0.38, 0.42, 0.24, 0.24)).fill()
            line([p(0.5, 0.68), p(0.5, 0.78)], width: 0.06)

        case .interiorLight:
            // Wagenkasten mit beleuchteten Fenstern
            let body = UIBezierPath(roundedRect: rect(0.06, 0.25, 0.88, 0.5), cornerRadius: 0.08 * s)
            body.lineWidth = 0.06 * s
            body.stroke()
            for i in 0..<3 {
                UIBezierPath(rect: rect(0.15 + CGFloat(i) * 0.25, 0.35, 0.18, 0.18)).fill()
            }
            line([p(0.25, 0.75), p(0.25, 0.85)])
            line([p(0.75, 0.75), p(0.75, 0.85)])

        case .sound:
            speaker()
            for (i, rr) in [CGFloat(0.16), 0.28].enumerated() {
                let arc = UIBezierPath(arcCenter: p(0.52, 0.5), radius: rr * s,
                                       startAngle: -.pi / 3.2, endAngle: .pi / 3.2, clockwise: true)
                arc.lineWidth = (0.06 - CGFloat(i) * 0.005) * s
                arc.lineCapStyle = .round
                arc.stroke()
            }

        case .mute:
            speaker()
            line([p(0.6, 0.36), p(0.88, 0.64)])
            line([p(0.88, 0.36), p(0.6, 0.64)])

        case .horn:
            // Signalhorn (Trichter)
            let path = UIBezierPath()
            path.move(to: p(0.1, 0.44))
            path.addLine(to: p(0.42, 0.44))
            path.addLine(to: p(0.88, 0.2))
            path.addLine(to: p(0.88, 0.8))
            path.addLine(to: p(0.42, 0.56))
            path.addLine(to: p(0.1, 0.56))
            path.close()
            path.fill()
            UIBezierPath(rect: rect(0.18, 0.56, 0.08, 0.2)).fill()

        case .whistle:
            // Dampfpfeife
            UIBezierPath(roundedRect: rect(0.36, 0.2, 0.28, 0.45), cornerRadius: 0.06 * s).fill()
            UIBezierPath(rect: rect(0.46, 0.65, 0.08, 0.22)).fill()
            UIBezierPath(rect: rect(0.3, 0.84, 0.4, 0.06)).fill()
            line([p(0.2, 0.15), p(0.28, 0.25)], width: 0.05)
            line([p(0.8, 0.15), p(0.72, 0.25)], width: 0.05)
            line([p(0.5, 0.05), p(0.5, 0.13)], width: 0.05)

        case .bell:
            let path = UIBezierPath()
            path.move(to: p(0.5, 0.12))
            path.addCurve(to: p(0.22, 0.7), controlPoint1: p(0.28, 0.12), controlPoint2: p(0.28, 0.45))
            path.addLine(to: p(0.14, 0.78))
            path.addLine(to: p(0.86, 0.78))
            path.addLine(to: p(0.78, 0.7))
            path.addCurve(to: p(0.5, 0.12), controlPoint1: p(0.72, 0.45), controlPoint2: p(0.72, 0.12))
            path.close()
            path.fill()
            UIBezierPath(ovalIn: rect(0.42, 0.78, 0.16, 0.14)).fill()

        case .announcement:
            // Mikrofon
            UIBezierPath(roundedRect: rect(0.38, 0.1, 0.24, 0.45), cornerRadius: 0.12 * s).fill()
            let arc = UIBezierPath(arcCenter: p(0.5, 0.42), radius: 0.22 * s, startAngle: 0, endAngle: .pi, clockwise: true)
            arc.lineWidth = 0.06 * s
            arc.stroke()
            line([p(0.5, 0.64), p(0.5, 0.86)], width: 0.06)
            line([p(0.32, 0.88), p(0.68, 0.88)], width: 0.06)

        case .shunting:
            // Schnecke für Rangiergang
            let shell = UIBezierPath(arcCenter: p(0.55, 0.5), radius: 0.24 * s, startAngle: .pi, endAngle: .pi * 2.9, clockwise: true)
            shell.lineWidth = 0.07 * s
            shell.stroke()
            UIBezierPath(ovalIn: rect(0.47, 0.42, 0.16, 0.16)).fill()
            line([p(0.08, 0.76), p(0.9, 0.76)], width: 0.07)
            line([p(0.12, 0.76), p(0.18, 0.55), p(0.24, 0.45)], width: 0.06)

        case .coupler:
            // Zwei Kupplungshaken
            line([p(0.06, 0.5), p(0.36, 0.5)], width: 0.08)
            line([p(0.36, 0.3), p(0.36, 0.7), p(0.46, 0.7)], width: 0.08)
            line([p(0.94, 0.5), p(0.64, 0.5)], width: 0.08)
            line([p(0.64, 0.7), p(0.64, 0.3), p(0.54, 0.3)], width: 0.08)

        case .smoke:
            UIBezierPath(rect: rect(0.38, 0.62, 0.24, 0.3)).fill()
            UIBezierPath(rect: rect(0.32, 0.58, 0.36, 0.07)).fill()
            UIBezierPath(ovalIn: rect(0.38, 0.32, 0.22, 0.2)).fill()
            UIBezierPath(ovalIn: rect(0.5, 0.16, 0.26, 0.22)).fill()
            UIBezierPath(ovalIn: rect(0.66, 0.04, 0.28, 0.22)).fill()

        case .brake:
            let circle = UIBezierPath(ovalIn: rect(0.24, 0.24, 0.52, 0.52))
            circle.lineWidth = 0.07 * s
            circle.stroke()
            let l = UIBezierPath(arcCenter: p(0.5, 0.5), radius: 0.4 * s, startAngle: .pi * 0.72, endAngle: .pi * 1.28, clockwise: true)
            l.lineWidth = 0.07 * s
            l.lineCapStyle = .round
            l.stroke()
            let rgt = UIBezierPath(arcCenter: p(0.5, 0.5), radius: 0.4 * s, startAngle: -.pi * 0.28, endAngle: .pi * 0.28, clockwise: true)
            rgt.lineWidth = 0.07 * s
            rgt.lineCapStyle = .round
            rgt.stroke()
            line([p(0.5, 0.34), p(0.5, 0.54)], width: 0.08)
            UIBezierPath(ovalIn: rect(0.46, 0.6, 0.08, 0.08)).fill()

        case .fan:
            for i in 0..<3 {
                let a = CGFloat(i) * .pi * 2 / 3
                let blade = UIBezierPath()
                blade.move(to: p(0.5, 0.5))
                let c1 = CGPoint(x: 0.5 * s + cos(a - 0.6) * 0.42 * s, y: 0.5 * s + sin(a - 0.6) * 0.42 * s)
                let c2 = CGPoint(x: 0.5 * s + cos(a + 0.3) * 0.42 * s, y: 0.5 * s + sin(a + 0.3) * 0.42 * s)
                blade.addQuadCurve(to: c2, controlPoint: c1)
                blade.close()
                blade.fill()
            }
            let ring = UIBezierPath(ovalIn: rect(0.06, 0.06, 0.88, 0.88))
            ring.lineWidth = 0.05 * s
            ring.stroke()

        case .door:
            let door = UIBezierPath(rect: rect(0.26, 0.1, 0.48, 0.8))
            door.lineWidth = 0.07 * s
            door.stroke()
            UIBezierPath(rect: rect(0.34, 0.2, 0.32, 0.25)).fill()
            UIBezierPath(ovalIn: rect(0.6, 0.52, 0.08, 0.08)).fill()

        case .pantograph:
            line([p(0.2, 0.15), p(0.8, 0.15)], width: 0.07)
            line([p(0.5, 0.15), p(0.3, 0.45), p(0.5, 0.75), p(0.7, 0.45), p(0.5, 0.15)], width: 0.06)
            line([p(0.5, 0.75), p(0.5, 0.85)], width: 0.06)
            UIBezierPath(rect: rect(0.25, 0.83, 0.5, 0.08)).fill()
        }
    }
}
