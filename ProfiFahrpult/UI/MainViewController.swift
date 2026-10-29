import UIKit

/// Hauptfenster im Aufbau der ECoS: oben die Statusleiste mit STOP (links) und GO (rechts),
/// im Querformat die beiden Fahrregler fest am linken und rechten Rand und dazwischen
/// die Menüleiste mit dem gewählten Bereich (Stellpult, Loks, Melder …).
/// Im Hochformat reicht der Platz dafür nicht; dann sind die Fahrregler die Seite „Fahren“.
final class MainViewController: UIViewController, Z21ClientObserver {

    private let client = Z21Client.shared

    private let topBar = GradientView(colors: [Theme.rgb(0x2B2F35), Theme.rgb(0x0B0C0E)], cornerRadius: 0, border: nil)
    private let topBarLine = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let connectionLED = StatusLED(frame: .zero)
    private let connectionLabel = UILabel()
    private let statusDisplay = GradientView(colors: [Theme.rgb(0x0C0E10), Theme.rgb(0x1A1D21)], cornerRadius: 6,
                                             border: Theme.panelBorder)
    private let statusLabel = UILabel()
    private let clockLabel = UILabel()
    private let stopButton = ECoSButton(title: "STOP", style: .red)
    private let goButton = ECoSButton(title: "GO", style: .green)
    private var clockTimer: Timer?

    private let menuBar = GradientView(colors: [Theme.menuTop, Theme.menuBottom], cornerRadius: 0, border: nil)
    private let container = UIView()
    private let driveController = DriveViewController()

    private struct Page {
        let title: String
        let icon: MenuIcon
        /// nil = die Fahrregler, die immer im Hauptfenster bleiben
        let make: (() -> UIViewController)?
    }

    private let pages: [Page] = [
        Page(title: "Fahren", icon: .drive, make: nil),
        Page(title: "Stellpult", icon: .switchboard) { SwitchboardViewController() },
        Page(title: "Loks", icon: .locos) { UINavigationController(rootViewController: LocoListViewController(style: .plain)) },
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
    /// Querformat: Fahrregler links und rechts, Menü in der Mitte
    private var isSplit = false

    override var prefersStatusBarHidden: Bool { return true }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        addChild(driveController)
        view.addSubview(driveController.view)
        driveController.didMove(toParent: self)
        view.addSubview(container)
        view.addSubview(menuBar)
        view.addSubview(topBar)
        topBarLine.backgroundColor = Theme.titleTop
        view.addSubview(topBarLine)

        titleLabel.text = "PROFI-FAHRPULT"
        titleLabel.font = Theme.font(16, bold: true)
        titleLabel.textColor = Theme.text
        subtitleLabel.text = "für Roco/Fleischmann Z21"
        subtitleLabel.font = Theme.font(11)
        subtitleLabel.textColor = Theme.textDim
        connectionLabel.font = Theme.font(12, bold: true)
        connectionLabel.textColor = Theme.textDim
        connectionLabel.adjustsFontSizeToFitWidth = true
        connectionLabel.minimumScaleFactor = 0.7
        statusLabel.font = Theme.font(17, bold: true)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.6
        statusDisplay.addSubview(statusLabel)
        clockLabel.font = Theme.monoFont(22, bold: true)
        clockLabel.textColor = Theme.text
        clockLabel.textAlignment = .center
        stopButton.titleLabel?.font = Theme.font(22, bold: true)
        goButton.titleLabel?.font = Theme.font(22, bold: true)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        goButton.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
        ([titleLabel, subtitleLabel, connectionLED, connectionLabel, statusDisplay, clockLabel,
          stopButton, goButton] as [UIView]).forEach {
            topBar.addSubview($0)
        }
        let statusTap = UITapGestureRecognizer(target: self, action: #selector(statusTapped))
        statusDisplay.addGestureRecognizer(statusTap)

        for (i, page) in pages.enumerated() {
            let b = MenuTabButton(title: page.title, icon: page.icon)
            b.tag = i
            b.addTarget(self, action: #selector(navTapped(_:)), for: .touchUpInside)
            menuBar.addSubview(b)
            navButtons.append(b)
        }

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

        isSplit = w > h && w >= 900
        if isSplit && currentPage == 0 {
            showPage(1)
        }

        // Statusleiste
        let barH: CGFloat = 60 + insets.top
        topBar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
        topBarLine.frame = CGRect(x: 0, y: barH, width: w, height: 2)

        let y0 = insets.top
        let btnW: CGFloat = w > 900 ? 130 : 104
        stopButton.frame = CGRect(x: insets.left + 10, y: y0 + 8, width: btnW, height: 44)
        goButton.frame = CGRect(x: w - insets.right - 10 - btnW, y: y0 + 8, width: btnW, height: 44)
        let clockW: CGFloat = 76
        clockLabel.frame = CGRect(x: goButton.frame.minX - 10 - clockW, y: y0 + 8, width: clockW, height: 44)

        var x = stopButton.frame.maxX + 14
        let showTitle = w >= 900
        titleLabel.isHidden = !showTitle
        subtitleLabel.isHidden = !showTitle
        if showTitle {
            titleLabel.frame = CGRect(x: x, y: y0 + 6, width: 180, height: 20)
            subtitleLabel.frame = CGRect(x: x, y: y0 + 25, width: 180, height: 14)
            connectionLED.frame = CGRect(x: x, y: y0 + 42, width: 12, height: 12)
            connectionLabel.frame = CGRect(x: x + 18, y: y0 + 40, width: 162, height: 16)
            x += 190
        } else {
            connectionLED.frame = CGRect(x: x, y: y0 + 24, width: 12, height: 12)
            connectionLabel.frame = .zero
            x += 22
        }
        statusDisplay.frame = CGRect(x: x, y: y0 + 9, width: max(100, clockLabel.frame.minX - 10 - x), height: 42)
        statusLabel.frame = statusDisplay.bounds.insetBy(dx: 10, dy: 0)

        // Inhalt
        let top = barH + 2
        let contentW = w - insets.left - insets.right
        let contentH = h - top - insets.bottom
        let sideW: CGFloat = isSplit ? min(380, max(270, floor(w * 0.27))) : 0
        driveController.sideWidth = sideW

        let centerX = insets.left + sideW
        let centerW = contentW - 2 * sideW
        let menuH: CGFloat = 62
        menuBar.frame = CGRect(x: centerX, y: top, width: centerW, height: menuH)
        container.frame = CGRect(x: centerX, y: top + menuH, width: centerW, height: contentH - menuH)
        if isSplit {
            driveController.view.frame = CGRect(x: insets.left, y: top, width: contentW, height: contentH)
        } else {
            driveController.view.frame = container.frame
        }
        driveController.view.isHidden = !isSplit && currentPage != 0
        container.isHidden = currentPage == 0

        let visible = navButtons.filter { !(isSplit && $0.tag == 0) }
        navButtons[0].isHidden = isSplit
        let tabGap: CGFloat = 6
        let tabW = floor((centerW - 12 - tabGap * CGFloat(visible.count - 1)) / CGFloat(visible.count))
        for (i, b) in visible.enumerated() {
            b.frame = CGRect(x: 6 + CGFloat(i) * (tabW + tabGap), y: 6, width: tabW, height: menuH - 12)
        }
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
        if let make = pages[index].make {
            let vc: UIViewController
            if let existing = controllers[index] {
                vc = existing
            } else {
                vc = make()
                controllers[index] = vc
            }
            addChild(vc)
            vc.view.frame = container.bounds
            vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(vc.view)
            vc.didMove(toParent: self)
        }
        currentPage = index
        for b in navButtons {
            b.isOn = b.tag == index
        }
        view.setNeedsLayout()
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
        switch client.connectionState {
        case .disconnected:
            connectionLED.color = Theme.red
            connectionLabel.text = "Nicht verbunden"
            text = "KEINE VERBINDUNG – hier tippen"
            color = Theme.textDim
        case .connecting:
            connectionLED.color = Theme.functionOn
            connectionLabel.text = "Verbinde mit \(client.host) …"
            text = "VERBINDE …"
            color = Theme.functionOn
        case .connected:
            connectionLED.color = Theme.green
            connectionLabel.text = "Z21 \(client.host)"
            switch client.trackStatus {
            case .on: text = "GLEISSPANNUNG EIN"; color = Theme.green
            case .off: text = "STOP – GLEISSPANNUNG AUS"; color = Theme.red
            case .emergencyStop: text = "NOTHALT – ALLE LOKS ANGEHALTEN"; color = Theme.red
            case .shortCircuit: text = "KURZSCHLUSS!"; color = Theme.red
            case .programming: text = "PROGRAMMIERMODUS"; color = Theme.functionOn
            case .unknown: text = "STATUS UNBEKANNT"; color = Theme.textDim
            }
        }
        statusLabel.text = text
        statusLabel.textColor = color
        let connected = client.connectionState == .connected
        stopButton.isEnabled = connected
        goButton.isEnabled = connected
        let stoppedStates: [TrackStatus] = [.off, .emergencyStop, .shortCircuit]
        let stopped = connected && stoppedStates.contains(client.trackStatus)
        stopButton.markColor = stopped ? UIColor.white : nil
        goButton.markColor = connected && client.trackStatus == .on ? UIColor.white : nil
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

/// Reiter der Menüleiste: Symbol über der Beschriftung, der gewählte Reiter leuchtet blau.
final class MenuTabButton: ECoSButton {

    private let icon: MenuIcon
    private let iconView = UIImageView()
    private let label = UILabel()

    init(title: String, icon: MenuIcon) {
        self.icon = icon
        super.init(frame: .zero)
        onColor = Theme.titleTop
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
        let color: UIColor = isOn ? .white : Theme.textDim
        label.textColor = color
        let size = min(26, iconView.bounds.height)
        iconView.image = size > 8 ? MenuTabButton.image(icon, size: size, color: color) : nil
    }

    private static var cache: [String: UIImage] = [:]

    static func image(_ icon: MenuIcon, size: CGFloat, color: UIColor) -> UIImage? {
        let key = "\(icon)-\(Int(size))-\(color == .white)"
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
