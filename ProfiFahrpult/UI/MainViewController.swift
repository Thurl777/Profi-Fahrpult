import UIKit

/// Hauptfenster wie das Display der ECoS: oben die blaue Menüleiste mit Symboltasten
/// (die gewählte leuchtet gelb), links daneben STOP und rechts GO als Gerätetasten,
/// darunter eine schmale Statuszeile und der gewählte Bereich. Unter „Fahren“ stehen die
/// beiden Fahrregler nebeneinander – im Hoch- und im Querformat.
final class MainViewController: UIViewController, Z21ClientObserver {

    private let client = Z21Client.shared

    private let menuBar = GradientView(colors: [Theme.menuTop, Theme.menuBottom], cornerRadius: 0, border: nil)
    private let menuLine = UIView()
    private let stopButton = ECoSButton(title: "STOP", style: .key)
    private let goButton = ECoSButton(title: "GO", style: .key)

    private let statusBar = UIView()
    private let connectionLED = StatusLED(frame: .zero)
    private let connectionLabel = UILabel()
    private let statusLabel = UILabel()
    private let clockLabel = UILabel()
    private var clockTimer: Timer?

    private let container = UIView()

    private struct Page {
        let title: String
        let icon: MenuIcon
        let make: () -> UIViewController
    }

    private let pages: [Page] = [
        Page(title: "Fahren", icon: .drive) { DriveViewController() },
        Page(title: "Loks", icon: .locos) { UINavigationController(rootViewController: LocoListViewController(style: .plain)) },
        Page(title: "Stellpult", icon: .switchboard) { SwitchboardViewController() },
        Page(title: "Melder", icon: .feedback) { FeedbackViewController() },
        Page(title: "Prog.", icon: .program) { ProgramViewController() },
        Page(title: "System", icon: .system) {
            let vc = SystemViewController()
            vc.title = "System"
            return UINavigationController(rootViewController: vc)
        }
    ]
    private var navButtons: [MenuTabButton] = []
    private var controllers: [Int: UIViewController] = [:]
    private var currentPage = -1

    override var prefersStatusBarHidden: Bool { return true }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        view.addSubview(container)
        view.addSubview(statusBar)
        view.addSubview(menuBar)
        menuLine.backgroundColor = Theme.titleLine
        view.addSubview(menuLine)

        for b in [stopButton, goButton] {
            b.titleLabel?.font = Theme.font(20, bold: true)
            menuBar.addSubview(b)
        }
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        goButton.addTarget(self, action: #selector(goTapped), for: .touchUpInside)

        for (i, page) in pages.enumerated() {
            let b = MenuTabButton(title: page.title, icon: page.icon)
            b.tag = i
            b.addTarget(self, action: #selector(navTapped(_:)), for: .touchUpInside)
            menuBar.addSubview(b)
            navButtons.append(b)
        }

        statusBar.backgroundColor = Theme.bar
        connectionLabel.font = Theme.font(12, bold: true)
        connectionLabel.textColor = .white
        statusLabel.font = Theme.font(14, bold: true)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.7
        clockLabel.font = Theme.monoFont(15, bold: true)
        clockLabel.textColor = .white
        clockLabel.textAlignment = .right
        ([connectionLED, connectionLabel, statusLabel, clockLabel] as [UIView]).forEach { statusBar.addSubview($0) }
        let statusTap = UITapGestureRecognizer(target: self, action: #selector(statusTapped))
        statusBar.addGestureRecognizer(statusTap)

        client.addObserver(self)
        showPage(0)
        updateStatus()
        updateClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
    }

    deinit {
        clockTimer?.invalidate()
        client.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = view.safeInsets
        let w = view.bounds.width
        let h = view.bounds.height

        // Menüleiste: STOP | Symboltasten | GO
        let barH: CGFloat = 60 + insets.top
        menuBar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
        menuLine.frame = CGRect(x: 0, y: barH, width: w, height: 1)
        let y0 = insets.top + 7
        let keyH: CGFloat = 46
        let keyW: CGFloat = w > 900 ? 110 : 88
        stopButton.frame = CGRect(x: insets.left + 10, y: y0, width: keyW, height: keyH)
        goButton.frame = CGRect(x: w - insets.right - 10 - keyW, y: y0, width: keyW, height: keyH)
        let tabsX = stopButton.frame.maxX + 16
        let tabsW = goButton.frame.minX - 16 - tabsX
        let tabGap: CGFloat = 8
        let count = CGFloat(navButtons.count)
        let tabW = min(120, floor((tabsW - tabGap * (count - 1)) / count))
        let startX = tabsX + (tabsW - (tabW * count + tabGap * (count - 1))) / 2
        for (i, b) in navButtons.enumerated() {
            b.frame = CGRect(x: startX + CGFloat(i) * (tabW + tabGap), y: y0, width: tabW, height: keyH)
        }

        // Statuszeile
        let statusH: CGFloat = 26
        statusBar.frame = CGRect(x: 0, y: barH + 1, width: w, height: statusH)
        let sx = insets.left + 12
        connectionLED.frame = CGRect(x: sx, y: 7, width: 12, height: 12)
        let sideW = min(220, floor(w * 0.25))
        connectionLabel.frame = CGRect(x: sx + 18, y: 0, width: sideW - 18, height: statusH)
        clockLabel.frame = CGRect(x: w - insets.right - 12 - 80, y: 0, width: 80, height: statusH)
        let statusX = sx + sideW
        statusLabel.frame = CGRect(x: statusX, y: 0, width: w - insets.right - 12 - sideW - statusX, height: statusH)

        let top = statusBar.frame.maxY
        container.frame = CGRect(x: insets.left, y: top, width: w - insets.left - insets.right,
                                 height: h - top - insets.bottom)
        controllers[currentPage]?.view.frame = container.bounds
    }

    // MARK: Navigation

    @objc private func navTapped(_ sender: MenuTabButton) {
        showPage(sender.tag)
    }

    private func showPage(_ index: Int) {
        guard index != currentPage else { return }
        if let old = controllers[currentPage] {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        let vc: UIViewController
        if let existing = controllers[index] {
            vc = existing
        } else {
            vc = pages[index].make()
            controllers[index] = vc
        }
        addChild(vc)
        vc.view.frame = container.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(vc.view)
        vc.didMove(toParent: self)
        currentPage = index
        for b in navButtons {
            b.isOn = b.tag == index
        }
    }

    // MARK: STOP / GO

    @objc private func stopTapped() {
        switch AppSettings.shared.stopButtonMode {
        case .trackPowerOff: client.setTrackPower(false)
        case .emergencyStop: client.emergencyStopAll()
        }
    }

    @objc private func goTapped() {
        client.setTrackPower(true)
    }

    @objc private func statusTapped() {
        if client.connectionState == .disconnected {
            showPage(pages.count - 1)
        }
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func updateClock() {
        clockLabel.text = MainViewController.clockFormatter.string(from: Date())
    }

    private func updateStatus() {
        let text: String
        let color: UIColor
        let lightGreen = Theme.rgb(0x9BF0A8)
        let lightRed = Theme.rgb(0xFFB3AE)
        switch client.connectionState {
        case .disconnected:
            connectionLED.color = Theme.red
            connectionLabel.text = "Nicht verbunden"
            text = "KEINE VERBINDUNG – hier tippen"
            color = .white
        case .connecting:
            connectionLED.color = Theme.functionOn
            connectionLabel.text = "Verbinde mit \(client.host) …"
            text = "VERBINDE …"
            color = Theme.functionOn
        case .connected:
            connectionLED.color = Theme.green
            connectionLabel.text = "Z21 \(client.host)"
            switch client.trackStatus {
            case .on: text = "GLEISSPANNUNG EIN"; color = lightGreen
            case .off: text = "STOP – GLEISSPANNUNG AUS"; color = lightRed
            case .emergencyStop: text = "NOTHALT – ALLE LOKS ANGEHALTEN"; color = lightRed
            case .shortCircuit: text = "KURZSCHLUSS!"; color = lightRed
            case .programming: text = "PROGRAMMIERMODUS"; color = Theme.functionOn
            case .unknown: text = "STATUS UNBEKANNT"; color = .white
            }
        }
        statusLabel.text = text
        statusLabel.textColor = color
        let connected = client.connectionState == .connected
        stopButton.isEnabled = connected
        goButton.isEnabled = connected
        // Wie an der ECoS leuchtet der Rahmen der aktiven Taste: STOP rot, GO grün
        let stoppedStates: [TrackStatus] = [.off, .emergencyStop, .shortCircuit]
        let stopped = connected && stoppedStates.contains(client.trackStatus)
        stopButton.markColor = stopped ? Theme.red : nil
        goButton.markColor = connected && client.trackStatus == .on ? Theme.green : nil
    }

    func z21ClientConnectionChanged(_ client: Z21Client) { updateStatus() }
    func z21ClientTrackStatusChanged(_ client: Z21Client) { updateStatus() }
}

/// Symbole der Menüleiste
enum MenuIcon {
    case drive
    case switchboard
    case locos
    case feedback
    case program
    case system
}

/// Taste der Menüleiste wie oben auf dem ECoS-Display: dunkel mit weißem Rand und weißem
/// Symbol, die gewählte Taste ist gelb mit dunklem Symbol.
final class MenuTabButton: ECoSButton {

    private let icon: MenuIcon
    private let iconView = UIImageView()
    private let label = UILabel()

    init(title: String, icon: MenuIcon) {
        self.icon = icon
        super.init(frame: .zero)
        onColor = Theme.functionOn
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        label.text = title
        label.font = Theme.font(12, bold: true)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.isUserInteractionEnabled = false
        addSubview(iconView)
        addSubview(label)
        accessibilityLabel = title
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var isOn: Bool {
        didSet { updateContent() }
    }

    private var lastSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 2, y: bounds.height - 17, width: bounds.width - 4, height: 14)
        iconView.frame = CGRect(x: 0, y: 2, width: bounds.width, height: bounds.height - 19)
        if bounds.size != lastSize {
            lastSize = bounds.size
            updateContent()
        }
    }

    private func updateContent() {
        let color: UIColor = isOn ? Theme.text : .white
        label.textColor = color
        let size = min(26, iconView.bounds.height)
        iconView.image = size > 8 ? MenuTabButton.image(icon, size: size, color: color) : nil
    }

    private static var cache: [String: UIImage] = [:]

    static func image(_ icon: MenuIcon, size: CGFloat, color: UIColor) -> UIImage? {
        let key = "\(icon)-\(Int(size))-\(color == UIColor.white)"
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

    private static func draw(_ icon: MenuIcon, s: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { return CGPoint(x: x * s, y: y * s) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            return CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
        }
        func line(_ pts: [CGPoint], width: CGFloat = 0.09) {
            let path = UIBezierPath()
            path.lineWidth = width * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: pts[0])
            for q in pts.dropFirst() { path.addLine(to: q) }
            path.stroke()
        }

        switch icon {
        case .drive:
            // Tacho mit Zeiger
            let arc = UIBezierPath(arcCenter: p(0.5, 0.58), radius: 0.4 * s,
                                   startAngle: .pi * 0.85, endAngle: .pi * 2.15, clockwise: true)
            arc.lineWidth = 0.09 * s
            arc.lineCapStyle = .round
            arc.stroke()
            line([p(0.5, 0.58), p(0.72, 0.32)])
            UIBezierPath(ovalIn: rect(0.42, 0.5, 0.16, 0.16)).fill()
        case .switchboard:
            // Weiche
            line([p(0.08, 0.7), p(0.92, 0.7)])
            line([p(0.32, 0.7), p(0.6, 0.42), p(0.92, 0.3)])
        case .locos:
            // Lok von der Seite
            UIBezierPath(roundedRect: rect(0.06, 0.38, 0.62, 0.3), cornerRadius: 0.04 * s).fill()
            UIBezierPath(roundedRect: rect(0.6, 0.2, 0.32, 0.48), cornerRadius: 0.05 * s).fill()
            for x in [CGFloat(0.2), 0.42, 0.74] {
                UIBezierPath(ovalIn: rect(x - 0.08, 0.68, 0.16, 0.16)).fill()
            }
        case .feedback:
            // Gleisabschnitt mit Belegtmeldung
            line([p(0.06, 0.78), p(0.94, 0.78)])
            for x in [CGFloat(0.18), 0.5, 0.82] {
                line([p(x, 0.68), p(x, 0.88)], width: 0.06)
            }
            UIBezierPath(ovalIn: rect(0.32, 0.12, 0.36, 0.36)).fill()
        case .program:
            // Decoder-Baustein
            let chip = UIBezierPath(roundedRect: rect(0.24, 0.24, 0.52, 0.52), cornerRadius: 0.05 * s)
            chip.lineWidth = 0.08 * s
            chip.stroke()
            for t in [CGFloat(0.36), 0.5, 0.64] {
                line([p(t, 0.06), p(t, 0.22)], width: 0.06)
                line([p(t, 0.78), p(t, 0.94)], width: 0.06)
                line([p(0.06, t), p(0.22, t)], width: 0.06)
                line([p(0.78, t), p(0.94, t)], width: 0.06)
            }
        case .system:
            // Schieberegler
            for (i, knob) in [CGFloat(0.3), 0.68, 0.45].enumerated() {
                let y = 0.22 + CGFloat(i) * 0.28
                line([p(0.08, y), p(0.92, y)], width: 0.07)
                UIBezierPath(ovalIn: rect(knob - 0.1, y - 0.1, 0.2, 0.2)).fill()
            }
        }
    }
}
