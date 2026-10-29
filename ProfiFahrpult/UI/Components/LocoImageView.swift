import UIKit

/// Zeigt das Lokfoto oder – falls keins hinterlegt ist – eine stilisierte Lok.
final class LocoImageView: UIView {

    var image: UIImage? {
        didSet {
            imageView.image = image
            imageView.isHidden = image == nil
            setNeedsDisplay()
        }
    }

    var isDimmed: Bool = false { didSet { setNeedsDisplay() } }

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.inset
        layer.cornerRadius = 4
        layer.borderColor = Theme.panelBorder.cgColor
        layer.borderWidth = 1
        clipsToBounds = true
        contentMode = .redraw
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        addSubview(imageView)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    override func draw(_ rect: CGRect) {
        guard image == nil else { return }
        let w = bounds.width
        let h = bounds.height
        let unit = min(w / 10, h / 4.5)
        let ox = (w - unit * 10) / 2
        let oy = (h - unit * 4.5) / 2
        func r(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat) -> CGRect {
            return CGRect(x: ox + x * unit, y: oy + y * unit, width: ww * unit, height: hh * unit)
        }
        let body = isDimmed ? Theme.textDark : Theme.rgb(0xB8232A)
        let dark = Theme.rgb(0x1A1C20)

        // Fahrgestell
        dark.setFill()
        UIBezierPath(rect: r(0.6, 3.0, 8.8, 0.5)).fill()
        // Aufbau (Diesellok mit Mittelführerstand)
        body.setFill()
        UIBezierPath(roundedRect: r(0.8, 1.6, 3.4, 1.4), cornerRadius: unit * 0.3).fill()
        UIBezierPath(roundedRect: r(5.8, 1.6, 3.4, 1.4), cornerRadius: unit * 0.3).fill()
        UIBezierPath(roundedRect: r(3.9, 0.5, 2.2, 2.5), cornerRadius: unit * 0.2).fill()
        // Fenster
        Theme.rgb(0xCFE3F5, alpha: isDimmed ? 0.4 : 0.9).setFill()
        UIBezierPath(rect: r(4.2, 0.85, 0.7, 0.7)).fill()
        UIBezierPath(rect: r(5.1, 0.85, 0.7, 0.7)).fill()
        // Zierstreifen
        UIColor(white: 1, alpha: isDimmed ? 0.3 : 0.85).setFill()
        UIBezierPath(rect: r(0.8, 2.5, 8.4, 0.15)).fill()
        // Drehgestelle mit Rädern
        dark.setFill()
        for x in [CGFloat(1.4), 2.8, 6.4, 7.8] {
            UIBezierPath(ovalIn: r(x - 0.45, 3.35, 0.9, 0.9)).fill()
        }
        Theme.textDim.setFill()
        for x in [CGFloat(1.4), 2.8, 6.4, 7.8] {
            UIBezierPath(ovalIn: r(x - 0.15, 3.65, 0.3, 0.3)).fill()
        }
    }
}
