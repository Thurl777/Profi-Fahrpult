import UIKit

/// Einmess-Hilfe: Die Lok fährt über ein Testgleis mit drei Belegtmeldern (links – Mitte – rechts).
/// Aus der Zeit zwischen den Meldern und den eingegebenen Streckenlängen ergibt sich die
/// Maßstabsgeschwindigkeit – wie die Messung mit Dauerkontakten in iTrain. Jede Fahrstufe kann
/// einzeln gemessen werden, oder die Lok fährt eine Reihe von Fahrstufen automatisch ab.
final class SpeedMeasureViewController: UIViewController, UITextFieldDelegate, Z21ClientObserver {

    /// Übernimmt einen Messpunkt in die Kennlinie
    var onAddPoint: ((SpeedPoint) -> Void)?

    private let loco: Locomotive
    private let client = Z21Client.shared
    private let settings = AppSettings.shared
    private let measurer: ContactSpeedMeasurer

    private var step: Int
    private var forward = true
    private var isDriving = false
    /// Gemessene Durchfahrten der aktuellen Fahrstufe (Einzeln-Modus)
    private var runs: [ContactRun] = []
    private var lastOccupied: [ContactPosition: Bool] = [.left: false, .middle: false, .right: false]
    /// Meldergruppen, deren Antwort auf `requestFeedback()` noch aussteht. Diese erste Antwort gibt
    /// nur den Ausgangszustand wieder und darf keine Durchfahrt auslösen.
    private var pendingSeedGroups: Set<UInt8> = []

    private enum Mode: Int { case manual = 0, automatic = 1 }
    private var mode: Mode = .manual

    private enum AutoState: Equatable {
        case idle
        case drivingForward(step: Int)
        case returning(step: Int)
        case settling(step: Int)
    }
    private var autoState: AutoState = .idle
    private var autoSteps: [Int] = []
    private var autoIndex = 0
    private var autoCaptured = 0
    private var autoLog: [String] = []

    private var autoCurrentStep: Int? {
        switch autoState {
        case .drivingForward(let s), .returning(let s), .settling(let s): return s
        case .idle: return nil
        }
    }

    private let scroll = UIScrollView()
    private let trackPanel = PanelView(title: "1  Messstrecke")
    private let locoPanel = PanelView(title: "2  Lok fahren lassen")
    private let contactPanel = PanelView(title: "3  Kontaktmessung")

    // Panel 1: Messstrecke
    private let scaleButton = ECoSButton(title: nil, style: .normal)
    private let trackConfigButton = ECoSButton(title: nil, style: .normal)
    private let ledLeft = StatusLED(frame: .zero)
    private let ledMiddle = StatusLED(frame: .zero)
    private let ledRight = StatusLED(frame: .zero)
    private let ledLeftLabel = UILabel()
    private let ledMiddleLabel = UILabel()
    private let ledRightLabel = UILabel()
    private let hintLabel = UILabel()

    // Panel 2: Lok fahren lassen
    private let stepLabel = UILabel()
    private let minusButton = ECoSButton(title: "−", style: .normal)
    private let plusButton = ECoSButton(title: "+", style: .normal)
    private let reverseButton = ECoSButton(title: "◀", style: .normal)
    private let forwardButton = ECoSButton(title: "▶", style: .normal)
    private let driveButton = ECoSButton(title: "Lok fahren", style: .green)
    private let stopButton = ECoSButton(title: "Lok anhalten / Abbrechen", style: .red)
    private let connectionLabel = UILabel()

    // Panel 3: Kontaktmessung
    private let modeControl = UISegmentedControl(items: ["Einzeln", "Automatisch"])
    private let statusLabel = UILabel()
    private let runsLabel = UILabel()
    private let takeButton = ECoSButton(title: "Als Messpunkt übernehmen", style: .green)
    private let clearRunsButton = ECoSButton(title: "Läufe löschen", style: .normal)

    private let autoFromLabel = UILabel()
    private let autoToLabel = UILabel()
    private let autoStepLabel = UILabel()
    private let autoFromField = UITextField()
    private let autoToField = UITextField()
    private let autoStepField = UITextField()
    private let autoStartButton = ECoSButton(title: "Automatik starten", style: .green)
    private let autoLogLabel = UILabel()

    init(loco: Locomotive) {
        self.loco = loco
        self.step = max(1, loco.speedSteps.maxStep / 2)
        self.measurer = ContactSpeedMeasurer(distanceLeftMiddleCm: AppSettings.shared.contactDistanceLeftMiddleCm,
                                             distanceMiddleRightCm: AppSettings.shared.contactDistanceMiddleRightCm,
                                             scale: AppSettings.shared.modelScale)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        client.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Einmessen: \(loco.name)"
        view.backgroundColor = Theme.background
        view.addSubview(scroll)
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        ([trackPanel, locoPanel, contactPanel] as [UIView]).forEach { scroll.addSubview($0) }
        client.addObserver(self)

        // 1 Messstrecke
        scaleButton.titleLabel?.font = Theme.font(16, bold: true)
        scaleButton.addTarget(self, action: #selector(chooseScale), for: .touchUpInside)
        trackConfigButton.titleLabel?.font = Theme.font(14, bold: true)
        trackConfigButton.titleLabel?.numberOfLines = 2
        trackConfigButton.titleLabel?.textAlignment = .center
        trackConfigButton.addTarget(self, action: #selector(configTrackTapped), for: .touchUpInside)
        for (led, label, text) in [(ledLeft, ledLeftLabel, "links"), (ledMiddle, ledMiddleLabel, "Mitte"),
                                    (ledRight, ledRightLabel, "rechts")] {
            label.text = text
            label.font = Theme.font(11, bold: true)
            label.textColor = Theme.textDim
            label.textAlignment = .center
        }
        hintLabel.text = "Drei Belegtmelder hintereinander auf einem geraden Gleisstück: links, Mitte, rechts. "
            + "Die Lok löst beim Überfahren nacheinander alle drei aus."
        hintLabel.font = Theme.font(13)
        hintLabel.textColor = Theme.textDim
        hintLabel.numberOfLines = 0
        ([scaleButton, trackConfigButton, ledLeft, ledMiddle, ledRight, ledLeftLabel, ledMiddleLabel, ledRightLabel,
          hintLabel] as [UIView]).forEach { trackPanel.contentView.addSubview($0) }

        // 2 Lok
        stepLabel.font = Theme.monoFont(24, bold: true)
        stepLabel.textColor = Theme.text
        stepLabel.textAlignment = .center
        stepLabel.backgroundColor = Theme.inset
        stepLabel.layer.cornerRadius = 4
        stepLabel.layer.borderWidth = 1
        stepLabel.layer.borderColor = Theme.panelBorder.cgColor
        stepLabel.clipsToBounds = true
        for b in [minusButton, plusButton] { b.titleLabel?.font = Theme.font(28, bold: true) }
        for b in [reverseButton, forwardButton] {
            b.titleLabel?.font = Theme.font(22, bold: true)
            b.onColor = Theme.functionOn
        }
        minusButton.addTarget(self, action: #selector(minusTapped), for: .touchUpInside)
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        reverseButton.addTarget(self, action: #selector(reverseTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        driveButton.addTarget(self, action: #selector(driveTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        connectionLabel.font = Theme.font(13)
        connectionLabel.textColor = Theme.red
        connectionLabel.numberOfLines = 0
        ([stepLabel, minusButton, plusButton, reverseButton, forwardButton, driveButton, stopButton, connectionLabel] as [UIView])
            .forEach { locoPanel.contentView.addSubview($0) }

        // 3 Kontaktmessung
        modeControl.selectedSegmentIndex = mode.rawValue
        modeControl.tintColor = Theme.accent
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        statusLabel.font = Theme.font(15, bold: true)
        statusLabel.textColor = Theme.accent
        statusLabel.numberOfLines = 0
        runsLabel.font = UIFont(name: "Menlo", size: 14) ?? Theme.font(14)
        runsLabel.textColor = Theme.text
        runsLabel.numberOfLines = 0
        takeButton.addTarget(self, action: #selector(takeTapped), for: .touchUpInside)
        clearRunsButton.addTarget(self, action: #selector(clearRunsTapped), for: .touchUpInside)

        for (label, text) in [(autoFromLabel, "von FS"), (autoToLabel, "bis FS"), (autoStepLabel, "Schrittweite")] {
            label.text = text
            label.font = Theme.font(12, bold: true)
            label.textColor = Theme.textDim
            label.textAlignment = .center
        }
        autoFromField.text = "1"
        autoToField.text = "\(loco.speedSteps.maxStep)"
        autoStepField.text = "10"
        for tf in [autoFromField, autoToField, autoStepField] {
            tf.backgroundColor = Theme.inset
            tf.textColor = Theme.text
            tf.font = Theme.monoFont(18, bold: true)
            tf.textAlignment = .center
            tf.keyboardType = .numberPad
            tf.keyboardAppearance = .light
            tf.layer.cornerRadius = 4
            tf.layer.borderWidth = 1
            tf.layer.borderColor = Theme.panelBorder.cgColor
            tf.delegate = self
        }
        autoStartButton.addTarget(self, action: #selector(autoStartTapped), for: .touchUpInside)
        autoLogLabel.font = UIFont(name: "Menlo", size: 13) ?? Theme.font(13)
        autoLogLabel.textColor = Theme.text
        autoLogLabel.numberOfLines = 0

        ([modeControl, statusLabel, runsLabel, takeButton, clearRunsButton, autoFromLabel, autoToLabel, autoStepLabel,
          autoFromField, autoToField, autoStepField, autoStartButton, autoLogLabel] as [UIView])
            .forEach { contactPanel.contentView.addSubview($0) }

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        updateAll()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        requestFeedbackSeed()
        measurer.distanceLeftMiddleCm = settings.contactDistanceLeftMiddleCm
        measurer.distanceMiddleRightCm = settings.contactDistanceMiddleRightCm
        measurer.scale = settings.modelScale
        seedOccupancyState()
        updateAll()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if autoState != .idle {
            finishAutomatic(aborted: true)
        } else if isDriving {
            stopTapped()
        }
    }

    // MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        let pad: CGFloat = 12
        let w = view.bounds.width - 2 * pad
        let inner = w - 24

        // 1 Messstrecke
        let half = floor((inner - 12) / 2)
        scaleButton.frame = CGRect(x: 12, y: 8, width: half, height: 52)
        trackConfigButton.frame = CGRect(x: 24 + half, y: 8, width: half, height: 52)
        let ledY: CGFloat = 68
        let ledSize: CGFloat = 20
        let ledSlot = inner / 3
        for (i, led) in [ledLeft, ledMiddle, ledRight].enumerated() {
            let cx = ledSlot * (CGFloat(i) + 0.5)
            led.frame = CGRect(x: 12 + cx - ledSize / 2, y: ledY, width: ledSize, height: ledSize)
        }
        for (i, label) in [ledLeftLabel, ledMiddleLabel, ledRightLabel].enumerated() {
            let cx = ledSlot * (CGFloat(i) + 0.5)
            label.frame = CGRect(x: 12 + cx - ledSlot / 2, y: ledY + ledSize + 2, width: ledSlot, height: 16)
        }
        let hintY: CGFloat = ledY + ledSize + 22
        let hintH = hintLabel.sizeThatFits(CGSize(width: inner, height: 200)).height
        hintLabel.frame = CGRect(x: 12, y: hintY, width: inner, height: hintH)
        trackPanel.frame = CGRect(x: pad, y: pad, width: w, height: PanelView.titleHeight + hintY + hintH + 12)

        // 2 Lok
        let small = floor((inner - 4 * 8) / 5)
        let mid = inner - 4 * 8 - 4 * small
        var x: CGFloat = 12
        for v in [reverseButton, minusButton] as [UIView] {
            v.frame = CGRect(x: x, y: 12, width: small, height: 52)
            x += small + 8
        }
        stepLabel.frame = CGRect(x: x, y: 12, width: mid, height: 52)
        x += mid + 8
        for v in [plusButton, forwardButton] as [UIView] {
            v.frame = CGRect(x: x, y: 12, width: small, height: 52)
            x += small + 8
        }
        driveButton.frame = CGRect(x: 12, y: 76, width: half, height: 52)
        stopButton.frame = CGRect(x: 24 + half, y: 76, width: half, height: 52)
        let connH = connectionLabel.text == nil ? 0 : connectionLabel.sizeThatFits(CGSize(width: inner, height: 200)).height
        connectionLabel.frame = CGRect(x: 12, y: 138, width: inner, height: connH)
        locoPanel.frame = CGRect(x: pad, y: trackPanel.frame.maxY + pad, width: w,
                                 height: PanelView.titleHeight + 138 + connH + (connH > 0 ? 12 : 0))

        // 3 Kontaktmessung
        modeControl.frame = CGRect(x: 12, y: 8, width: inner, height: 36)
        statusLabel.frame = CGRect(x: 12, y: 52, width: inner, height: statusLabel.sizeThatFits(CGSize(width: inner, height: 60)).height)
        var y = statusLabel.frame.maxY + 10
        let contactHeight: CGFloat
        if mode == .manual {
            let runsH = runsLabel.sizeThatFits(CGSize(width: inner, height: 1000)).height
            runsLabel.frame = CGRect(x: 12, y: y, width: inner, height: runsH)
            y += runsH + 12
            takeButton.frame = CGRect(x: 12, y: y, width: inner - 160 - 12, height: 52)
            clearRunsButton.frame = CGRect(x: inner - 160 + 12, y: y, width: 160, height: 52)
            contactHeight = y + 52 + 12
        } else {
            let fieldW = floor((inner - 2 * 12) / 3)
            autoFromLabel.frame = CGRect(x: 12, y: y, width: fieldW, height: 16)
            autoToLabel.frame = CGRect(x: 24 + fieldW, y: y, width: fieldW, height: 16)
            autoStepLabel.frame = CGRect(x: 36 + 2 * fieldW, y: y, width: fieldW, height: 16)
            y += 18
            autoFromField.frame = CGRect(x: 12, y: y, width: fieldW, height: 44)
            autoToField.frame = CGRect(x: 24 + fieldW, y: y, width: fieldW, height: 44)
            autoStepField.frame = CGRect(x: 36 + 2 * fieldW, y: y, width: fieldW, height: 44)
            y += 44 + 12
            autoStartButton.frame = CGRect(x: 12, y: y, width: inner, height: 52)
            y += 52 + 12
            let logH = max(20, autoLogLabel.sizeThatFits(CGSize(width: inner, height: 2000)).height)
            autoLogLabel.frame = CGRect(x: 12, y: y, width: inner, height: logH)
            contactHeight = y + logH + 12
        }
        contactPanel.frame = CGRect(x: pad, y: locoPanel.frame.maxY + pad, width: w,
                                    height: PanelView.titleHeight + contactHeight)

        scroll.contentSize = CGSize(width: view.bounds.width, height: contactPanel.frame.maxY + pad)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: Anzeige

    private var averageKmh: Double? {
        guard !runs.isEmpty else { return nil }
        return runs.map { $0.kmh }.reduce(0, +) / Double(runs.count)
    }

    private func updateAll() {
        scaleButton.setTitle("Maßstab: \(settings.modelScale.title)", for: .normal)
        trackConfigButton.setTitle(settings.contactTrackConfigured
            ? "Messgleis: eingerichtet\n(bearbeiten)" : "Messgleis einrichten …", for: .normal)
        trackConfigButton.style = settings.contactTrackConfigured ? .normal : .accent

        stepLabel.text = "FS \(step)/\(loco.speedSteps.maxStep)"
        forwardButton.isOn = forward
        reverseButton.isOn = !forward
        let connected = client.connectionState == .connected
        let autoActive = autoState != .idle
        let manualControlsEnabled = connected && mode == .manual && !autoActive
        minusButton.isEnabled = manualControlsEnabled && step > 1
        plusButton.isEnabled = manualControlsEnabled && step < loco.speedSteps.maxStep
        reverseButton.isEnabled = manualControlsEnabled
        forwardButton.isEnabled = manualControlsEnabled
        driveButton.isEnabled = manualControlsEnabled
        stopButton.isEnabled = connected && (isDriving || autoActive)
        driveButton.markColor = isDriving ? Theme.text : nil
        connectionLabel.text = connected ? nil
            : "Nicht mit der Z21 verbunden. Ohne Verbindung ist weder manuelles noch automatisches Messen möglich."

        modeControl.isEnabled = !autoActive
        runsLabel.isHidden = mode != .manual
        takeButton.isHidden = mode != .manual
        clearRunsButton.isHidden = mode != .manual
        [autoFromLabel, autoToLabel, autoStepLabel, autoFromField, autoToField, autoStepField, autoStartButton,
         autoLogLabel].forEach { $0.isHidden = mode != .automatic }
        autoStartButton.setTitle(autoActive ? "Automatik läuft …" : "Automatik starten", for: .normal)
        autoStartButton.isEnabled = mode == .automatic && connected && !autoActive && settings.contactTrackConfigured
        [autoFromField, autoToField, autoStepField].forEach { $0.isEnabled = !autoActive }

        if mode == .manual {
            if runs.isEmpty {
                runsLabel.text = "Noch keine Durchfahrt bei Fahrstufe \(step). Lok über die Messstrecke fahren lassen."
                runsLabel.textColor = Theme.textDim
            } else {
                var lines: [String] = []
                for (i, r) in runs.enumerated() {
                    lines.append("Durchfahrt \(i + 1):  \(SpeedFormat.kmh(r.kmh))  (\(r.forward ? "vorwärts" : "rückwärts"))")
                }
                if let avg = averageKmh {
                    lines.append("Mittelwert:  \(SpeedFormat.kmh(avg))")
                }
                runsLabel.text = lines.joined(separator: "\n")
                runsLabel.textColor = Theme.text
            }
            takeButton.isEnabled = averageKmh != nil
            takeButton.setTitle("Fahrstufe \(step) als Messpunkt übernehmen", for: .normal)
            clearRunsButton.isEnabled = !runs.isEmpty
        } else {
            autoLogLabel.text = autoLog.isEmpty ? "Noch keine Messpunkte in diesem Lauf." : autoLog.joined(separator: "\n")
        }
        view.setNeedsLayout()
    }

    private func updateLEDs() {
        ledLeft.color = color(for: .left)
        ledMiddle.color = color(for: .middle)
        ledRight.color = color(for: .right)
    }

    private func color(for position: ContactPosition) -> UIColor {
        return (lastOccupied[position] ?? false) ? Theme.functionOn : Theme.rgb(0x5A5F6B)
    }

    // MARK: Messstrecke

    @objc private func chooseScale() {
        let sheet = UIAlertController(title: "Maßstab der Anlage", message: nil, preferredStyle: .actionSheet)
        for scale in ModelScale.allCases {
            let title = scale == settings.modelScale ? "✓ " + scale.title : scale.title
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.settings.modelScale = scale
                self.measurer.scale = scale
                self.updateAll()
            })
        }
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = scaleButton
        sheet.popoverPresentationController?.sourceRect = scaleButton.bounds
        present(sheet, animated: true, completion: nil)
    }

    @objc private func configTrackTapped() {
        navigationController?.pushViewController(ContactTrackConfigViewController(), animated: true)
    }

    // MARK: Lok (Panel 2)

    private func setStep(_ newStep: Int) {
        let clamped = max(1, min(newStep, loco.speedSteps.maxStep))
        guard clamped != step else { return }
        step = clamped
        runs = []           // Durchfahrten gehören immer zu einer Fahrstufe
        measurer.reset()
        if isDriving {
            sendDrive()
        }
        updateAll()
    }

    private func sendDrive() {
        client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: step, forward: forward)
    }

    @objc private func minusTapped() { setStep(step - 1) }
    @objc private func plusTapped() { setStep(step + 1) }

    @objc private func reverseTapped() {
        forward = false
        if isDriving { sendDrive() }
        updateAll()
    }

    @objc private func forwardTapped() {
        forward = true
        if isDriving { sendDrive() }
        updateAll()
    }

    @objc private func driveTapped() {
        view.endEditing(true)
        guard client.connectionState == .connected else { return }
        client.subscribeLoco(loco.address)
        isDriving = true
        measurer.reset()
        sendDrive()
        updateAll()
    }

    @objc private func stopTapped() {
        if autoState != .idle {
            finishAutomatic(aborted: true)
            return
        }
        client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: 0, forward: forward)
        isDriving = false
        updateAll()
    }

    // MARK: Kontaktmessung (Panel 3)

    @objc private func modeChanged() {
        guard let m = Mode(rawValue: modeControl.selectedSegmentIndex) else { return }
        if autoState != .idle { finishAutomatic(aborted: true) }
        mode = m
        runs = []
        measurer.reset()
        statusLabel.text = mode == .manual ? "Bereit für eine Durchfahrt." : "Bereit für die Automatik."
        updateAll()
    }

    @objc private func takeTapped() {
        guard let avg = averageKmh else { return }
        onAddPoint?(SpeedPoint(step: step, maxStep: loco.speedSteps.maxStep, kmh: avg))
        let count = runs.count
        runs = []
        measurer.reset()
        updateAll()
        statusLabel.text = "Fahrstufe \(step) = \(SpeedFormat.kmh(avg)) übernommen (\(count) Durchfahrten)"
    }

    @objc private func clearRunsTapped() {
        runs = []
        measurer.reset()
        updateAll()
    }

    private func recordRun(_ run: ContactRun) {
        runs.append(run)
        statusLabel.text = "Messung: \(SpeedFormat.kmh(run.kmh)) (\(run.forward ? "vorwärts" : "rückwärts"))"
        updateAll()
        if mode == .automatic {
            handleAutomaticRun(run)
        }
    }

    // MARK: Automatik

    @objc private func autoStartTapped() {
        guard settings.contactTrackConfigured else {
            showMessage("Messgleis nicht eingerichtet", "Bitte zuerst die drei Melderadressen und Streckenlängen eintragen.")
            return
        }
        guard client.connectionState == .connected else { return }
        view.endEditing(true)
        let from = Int(autoFromField.text ?? "") ?? 1
        let to = Int(autoToField.text ?? "") ?? loco.speedSteps.maxStep
        let inc = max(1, Int(autoStepField.text ?? "") ?? 10)
        let lo = max(1, min(from, to))
        let hi = min(loco.speedSteps.maxStep, max(from, to))
        guard lo <= hi else {
            showMessage("Ungültiger Bereich", "„von FS“ und „bis FS“ prüfen.")
            return
        }
        var steps = Array(stride(from: lo, through: hi, by: inc))
        if steps.last != hi { steps.append(hi) }
        autoSteps = steps
        autoIndex = 0
        autoCaptured = 0
        autoLog = []
        measurer.reset()
        client.subscribeLoco(loco.address)
        beginAutomaticStep()
    }

    private func beginAutomaticStep() {
        guard autoIndex < autoSteps.count else {
            finishAutomatic(aborted: false)
            return
        }
        let s = autoSteps[autoIndex]
        autoState = .drivingForward(step: s)
        step = s
        forward = true
        isDriving = true
        measurer.reset()
        sendDrive()
        runs = []
        statusLabel.text = "Automatik: Fahrstufe \(s) (\(autoIndex + 1)/\(autoSteps.count)) – fährt vorwärts durch die Messstrecke …"
        updateAll()
    }

    private func handleAutomaticRun(_ run: ContactRun) {
        guard case .drivingForward(let s) = autoState, run.forward else { return }
        onAddPoint?(SpeedPoint(step: s, maxStep: loco.speedSteps.maxStep, kmh: run.kmh))
        autoCaptured += 1
        autoLog.append("FS \(s) → \(SpeedFormat.kmh(run.kmh))")
        autoState = .returning(step: s)
        forward = false
        sendDrive()
        statusLabel.text = "Automatik: Fahrstufe \(s) gemessen – fährt zurück zum Start …"
        updateAll()
    }

    private func handleLeftCleared() {
        guard case .returning = autoState, let s = autoCurrentStep else { return }
        autoState = .settling(step: s)
        client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: 0, forward: forward)
        isDriving = false
        statusLabel.text = "Automatik: Lok angehalten – kurze Pause …"
        updateAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.advanceAutomatic()
        }
    }

    private func advanceAutomatic() {
        guard case .settling = autoState else { return }
        autoIndex += 1
        beginAutomaticStep()
    }

    private func finishAutomatic(aborted: Bool) {
        let wasActive = autoState != .idle
        autoState = .idle
        isDriving = false
        if wasActive {
            client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: 0, forward: forward)
        }
        statusLabel.text = aborted ? "Automatik abgebrochen (\(autoCaptured) Messpunkte übernommen)"
                                    : "Automatik fertig: \(autoCaptured) Messpunkte übernommen"
        updateAll()
    }

    // MARK: Kontaktauswertung

    private func address(for position: ContactPosition) -> Int {
        switch position {
        case .left: return settings.contactAddressLeft
        case .middle: return settings.contactAddressMiddle
        case .right: return settings.contactAddressRight
        }
    }

    private func currentOccupancy(for position: ContactPosition) -> Bool? {
        let addr = address(for: position)
        guard addr >= 1, addr <= 160 else { return nil }
        let module = (addr - 1) / 8 + 1
        let input = (addr - 1) % 8 + 1
        return client.feedbackOccupied(module: module, input: input)
    }

    private func requestFeedbackSeed() {
        guard client.connectionState == .connected else { return }
        pendingSeedGroups = [0, 1]
        client.requestFeedback()
    }

    private func seedOccupancyState() {
        for position: ContactPosition in [.left, .middle, .right] {
            lastOccupied[position] = currentOccupancy(for: position) ?? false
        }
        updateLEDs()
    }

    private func refreshContactStates() {
        for position: ContactPosition in [.left, .middle, .right] {
            guard let occ = currentOccupancy(for: position) else { continue }
            let was = lastOccupied[position] ?? false
            if occ != was {
                lastOccupied[position] = occ
                if occ {
                    handleRisingEdge(position)
                } else if position == .left {
                    handleLeftCleared()
                }
            }
        }
        updateLEDs()
    }

    private func handleRisingEdge(_ position: ContactPosition) {
        guard settings.contactTrackConfigured else { return }
        let label: String
        switch position {
        case .left: label = "links"
        case .middle: label = "Mitte"
        case .right: label = "rechts"
        }
        if let run = measurer.occupied(position, at: CACurrentMediaTime()) {
            recordRun(run)
        } else {
            statusLabel.text = "Kontakt \(label) ausgelöst – Durchfahrt läuft …"
        }
    }

    // MARK: Z21ClientObserver

    func z21Client(_ client: Z21Client, feedbackChangedInGroup group: UInt8) {
        if pendingSeedGroups.remove(group) != nil {
            seedOccupancyState()
            return
        }
        refreshContactStates()
    }

    func z21ClientConnectionChanged(_ client: Z21Client) {
        if client.connectionState == .connected {
            requestFeedbackSeed()
            client.subscribeLoco(loco.address)
        } else if autoState != .idle {
            finishAutomatic(aborted: true)
        }
        updateAll()
    }
}
