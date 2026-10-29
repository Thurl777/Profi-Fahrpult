import UIKit

/// Farben und Schriften im Stil der ESU ECoS: dunkler Hintergrund,
/// graue Verlaufsflächen, blaue Titelleisten, gelb leuchtende Funktionen.
enum Theme {

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255,
                       alpha: alpha)
    }

    static let background = rgb(0x08090B)
    static let panelTop = rgb(0x3A3E44)
    static let panelBottom = rgb(0x25282C)
    static let panelBorder = rgb(0x55595F)
    static let inset = rgb(0x0B0C0E)

    static let titleTop = rgb(0x3A72BF)
    static let titleBottom = rgb(0x1D4583)

    /// Menüleiste zwischen den beiden Fahrreglern
    static let menuTop = rgb(0x30343A)
    static let menuBottom = rgb(0x17191C)

    static let buttonTop = rgb(0x62666D)
    static let buttonBottom = rgb(0x383B40)
    static let buttonPressedTop = rgb(0x2A5FA8)
    static let buttonPressedBottom = rgb(0x1A3D73)

    static let accent = rgb(0x3D8BFF)
    static let functionOn = rgb(0xFFC21A)
    static let functionOnDark = rgb(0xB57E00)

    static let red = rgb(0xD9261C)
    static let redDark = rgb(0x8A1009)
    static let green = rgb(0x2DB843)
    static let greenDark = rgb(0x146B22)

    static let text = UIColor.white
    static let textDim = rgb(0xA4A9B0)
    static let textDark = rgb(0x6E737A)

    static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
    }

    static func monoFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
        return UIFont.monospacedDigitSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// Einheitliches Aussehen der System-Steuerelemente
    static func applyAppearance() {
        UINavigationBar.appearance().barTintColor = titleBottom
        UINavigationBar.appearance().tintColor = .white
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().barStyle = .black
        UITableView.appearance().backgroundColor = background
        UITableView.appearance().separatorColor = panelBorder
        UISwitch.appearance().onTintColor = accent
        UITextField.appearance().keyboardAppearance = .dark
    }

    static func styleCell(_ cell: UITableViewCell) {
        cell.backgroundColor = panelBottom
        cell.textLabel?.textColor = text
        cell.detailTextLabel?.textColor = textDim
        cell.tintColor = accent
        let sel = UIView()
        sel.backgroundColor = buttonPressedBottom
        cell.selectedBackgroundView = sel
    }
}

/// Fläche mit vertikalem Farbverlauf und Rahmen
class GradientView: UIView {

    override class var layerClass: AnyClass { return CAGradientLayer.self }

    var gradientLayer: CAGradientLayer {
        // swiftlint:disable:next force_cast
        return layer as! CAGradientLayer
    }

    var colors: [UIColor] = [Theme.panelTop, Theme.panelBottom] {
        didSet { gradientLayer.colors = colors.map { $0.cgColor } }
    }

    init(colors: [UIColor] = [Theme.panelTop, Theme.panelBottom], cornerRadius: CGFloat = 6, border: UIColor? = Theme.panelBorder) {
        super.init(frame: .zero)
        self.colors = colors
        gradientLayer.colors = colors.map { $0.cgColor }
        layer.cornerRadius = cornerRadius
        if let border = border {
            layer.borderColor = border.cgColor
            layer.borderWidth = 1
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        gradientLayer.colors = colors.map { $0.cgColor }
    }
}

/// Panel mit blauer Titelleiste wie die Fenster der ECoS
class PanelView: GradientView {

    let titleBar = GradientView(colors: [Theme.titleTop, Theme.titleBottom], cornerRadius: 0, border: nil)
    let titleLabel = UILabel()
    let contentView = UIView()
    static let titleHeight: CGFloat = 30

    var title: String? {
        get { return titleLabel.text }
        set { titleLabel.text = newValue }
    }

    init(title: String?) {
        super.init(colors: [Theme.panelTop, Theme.panelBottom], cornerRadius: 6, border: Theme.panelBorder)
        clipsToBounds = true
        titleLabel.text = title
        titleLabel.font = Theme.font(14, bold: true)
        titleLabel.textColor = .white
        titleBar.addSubview(titleLabel)
        addSubview(titleBar)
        addSubview(contentView)
        titleBar.isHidden = title == nil
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let th = titleBar.isHidden ? 0 : PanelView.titleHeight
        titleBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: th)
        titleLabel.frame = titleBar.bounds.insetBy(dx: 10, dy: 0)
        contentView.frame = CGRect(x: 0, y: th, width: bounds.width, height: bounds.height - th)
    }
}

/// Taste mit Verlauf. `isOn` schaltet die Leuchtfarbe (z.B. aktive Funktion) ein.
class ECoSButton: UIButton {

    enum Style {
        case normal
        case red
        case green
        case accent
    }

    var style: Style = .normal { didSet { updateColors() } }
    var isOn: Bool = false { didSet { updateColors() } }
    /// Farbe im eingeschalteten Zustand
    var onColor: UIColor = Theme.functionOn { didSet { updateColors() } }
    /// Hervorhebungsrahmen, z.B. für die aktuelle Weichenstellung
    var markColor: UIColor? { didSet { updateColors() } }

    private let gradient = CAGradientLayer()

    convenience init(title: String?, style: Style = .normal) {
        self.init(frame: .zero)
        self.style = style
        setTitle(title, for: .normal)
        setup()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private var didSetup = false

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        layer.insertSublayer(gradient, at: 0)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = Theme.panelBorder.cgColor
        clipsToBounds = true
        titleLabel?.font = Theme.font(15, bold: true)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.6
        setTitleColor(.white, for: .normal)
        setTitleColor(Theme.textDark, for: .disabled)
        updateColors()
    }

    override var isHighlighted: Bool { didSet { updateColors() } }
    override var isEnabled: Bool { didSet { updateColors() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    private func updateColors() {
        var top: UIColor
        var bottom: UIColor
        switch style {
        case .normal: top = Theme.buttonTop; bottom = Theme.buttonBottom
        case .red: top = Theme.red; bottom = Theme.redDark
        case .green: top = Theme.green; bottom = Theme.greenDark
        case .accent: top = Theme.titleTop; bottom = Theme.titleBottom
        }
        if isOn {
            top = onColor
            bottom = onColor.withBrightnessFactor(0.6)
        }
        if isHighlighted {
            if style == .normal && !isOn {
                top = Theme.buttonPressedTop
                bottom = Theme.buttonPressedBottom
            } else {
                top = top.withBrightnessFactor(0.7)
                bottom = bottom.withBrightnessFactor(0.7)
            }
        }
        if !isEnabled {
            top = top.withBrightnessFactor(0.55)
            bottom = bottom.withBrightnessFactor(0.55)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [top.cgColor, bottom.cgColor]
        CATransaction.commit()
        if let mark = markColor {
            layer.borderColor = mark.cgColor
            layer.borderWidth = 3
        } else {
            layer.borderColor = (isOn ? onColor.withBrightnessFactor(1.2) : Theme.panelBorder).cgColor
            layer.borderWidth = 1
        }
        let titleColor: UIColor = isOn && style == .normal ? .black : .white
        setTitleColor(titleColor, for: .normal)
        tintColor = titleColor
    }
}

/// Runde Statusleuchte
class StatusLED: UIView {
    var color: UIColor = Theme.textDark {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ rect: CGRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = UIBezierPath(ovalIn: r)
        color.setFill()
        path.fill()
        UIColor(white: 1, alpha: 0.35).setFill()
        UIBezierPath(ovalIn: CGRect(x: r.minX + r.width * 0.25, y: r.minY + r.height * 0.12,
                                    width: r.width * 0.5, height: r.height * 0.35)).fill()
        UIColor.black.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

extension UIColor {
    func withBrightnessFactor(_ factor: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: min(r * factor, 1), green: min(g * factor, 1), blue: min(b * factor, 1), alpha: a)
    }
}

extension UIView {
    /// Sicherer Bereich, ab iOS 11 über safeAreaInsets, davor ohne Einzug
    var safeInsets: UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return safeAreaInsets
        }
        return .zero
    }
}

extension UIViewController {
    func showMessage(_ title: String, _ message: String? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
