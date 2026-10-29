import UIKit

/// Hauptfenster: Statusleiste mit STOP/GO oben, Navigationsleiste links, Inhalt rechts.
final class MainViewController: UIViewController, Z21ClientObserver {

    private let client = Z21Client.shared

    private let topBar = GradientView(colors: [Theme.rgb(0x2E3238), Theme.rgb(0x16181B)], cornerRadius: 0, border: nil)
    private let topBarLine = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let connectionLED = StatusLED(frame: .zero)
    private let connectionLabel = UILabel()
    private let statusDisplay = GradientView(colors: [Theme.rgb(0x0C0E10), Theme.rgb(0x1A1D21)], cornerRadius: 6,
                                             border: Theme.panelBorder)
    private let statusLabel = UILabel()
    private let stopButton = ECoSButton(title: "STOP", style: .red)
    private let goButton = ECoSButton(title: "GO", style: .green)

    private let sideBar = GradientView(colors: [Theme.rgb(0x26292E), Theme.rgb(0x16181B)], cornerRadius: 0, border: nil)
    private let container = UIView()

    private struct Page {
        let title: String
        let make: () -> UIViewController
    }

    private let pages: [Page] = [
        Page(title: "Fahren") { DriveViewController() },
        Page(title: "Loks") { UINavigationController(rootViewController: LocoListViewController(style: .plain)) },
        Page(title: "Stellpult") { SwitchboardViewController() },
        Page(title: "Melder") { FeedbackViewController() },
        Page(title: "Prog.") { ProgramViewController() },
        Page(title: "System") {
            let vc = SystemViewController()
            vc.title = "System"
            return UINavigationController(rootViewController: vc)
        }
    ]
    private var navButtons: [ECoSButton] = []
    private var controllers: [Int: UIViewController] = [:]
    private var currentPage = -1

    override var prefersStatusBarHidden: Bool { return true }
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        view.addSubview(container)
        view.addSubview(sideBar)
        view.addSubview(topBar)
        topBarLine.backgroundColor = Theme.titleTop
        view.addSubview(topBarLine)

        titleLabel.text = "PROFI-FAHRPULT"
        titleLabel.font = Theme.font(18, bold: true)
        titleLabel.textColor = Theme.text
        subtitleLabel.text = "für Roco/Fleischmann Z21"
        subtitleLabel.font = Theme.font(11)
        subtitleLabel.textColor = Theme.textDim
        connectionLabel.font = Theme.font(12, bold: true)
        connectionLabel.textColor = Theme.textDim
        statusLabel.font = Theme.font(17, bold: true)
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.6
        statusDisplay.addSubview(statusLabel)
        stopButton.titleLabel?.font = Theme.font(22, bold: true)
        goButton.titleLabel?.font = Theme.font(22, bold: true)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        goButton.addTarget(self, action: #selector(goTapped), for: .touchUpInside)
        ([titleLabel, subtitleLabel, connectionLED, connectionLabel, statusDisplay, stopButton, goButton] as [UIView]).forEach {
            topBar.addSubview($0)
        }
        let statusTap = UITapGestureRecognizer(target: self, action: #selector(statusTapped))
        statusDisplay.addGestureRecognizer(statusTap)

        for (i, page) in pages.enumerated() {
            let b = ECoSButton(title: page.title, style: .normal)
            b.tag = i
            b.onColor = Theme.accent
            b.titleLabel?.font = Theme.font(15, bold: true)
            b.addTarget(self, action: #selector(navTapped(_:)), for: .touchUpInside)
            sideBar.addSubview(b)
            navButtons.append(b)
        }

        client.addObserver(self)
        showPage(0)
        updateStatus()
    }

    deinit {
        client.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = view.safeInsets
        let w = view.bounds.width
        let h = view.bounds.height
        let barH: CGFloat = 64 + insets.top
        let sideW: CGFloat = 96 + insets.left

        topBar.frame = CGRect(x: 0, y: 0, width: w, height: barH)
        topBarLine.frame = CGRect(x: 0, y: barH, width: w, height: 2)
        sideBar.frame = CGRect(x: 0, y: barH + 2, width: sideW, height: h - barH - 2)
        container.frame = CGRect(x: sideW, y: barH + 2, width: w - sideW - insets.right,
                                 height: h - barH - 2 - insets.bottom)

        let y0 = insets.top
        let left = insets.left + 14
        titleLabel.frame = CGRect(x: left, y: y0 + 8, width: 200, height: 22)
        subtitleLabel.frame = CGRect(x: left, y: y0 + 29, width: 200, height: 14)
        connectionLED.frame = CGRect(x: left, y: y0 + 45, width: 12, height: 12)
        connectionLabel.frame = CGRect(x: left + 18, y: y0 + 43, width: 200, height: 16)

        let btnW: CGFloat = w > 900 ? 120 : 96
        goButton.frame = CGRect(x: w - insets.right - 10 - btnW, y: y0 + 8, width: btnW, height: 48)
        stopButton.frame = CGRect(x: goButton.frame.minX - 10 - btnW, y: y0 + 8, width: btnW, height: 48)
        let statusX = left + 210
        statusDisplay.frame = CGRect(x: statusX, y: y0 + 10, width: max(100, stopButton.frame.minX - 16 - statusX), height: 44)
        statusLabel.frame = statusDisplay.bounds.insetBy(dx: 10, dy: 0)

        let navH: CGFloat = 64
        for (i, b) in navButtons.enumerated() {
            b.frame = CGRect(x: insets.left + 8, y: 10 + CGFloat(i) * (navH + 8), width: 80, height: navH)
        }
        controllers[currentPage]?.view.frame = container.bounds
    }

    // MARK: Navigation

    @objc private func navTapped(_ sender: ECoSButton) {
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
