import UIKit

/// Einmess-Hilfe: Die Lok fährt mit fester Fahrstufe über eine bekannte Strecke,
/// Start und Ziel werden per Stoppuhr getippt, daraus folgt die Maßstabsgeschwindigkeit.
final class SpeedMeasureViewController: UIViewController, UITextFieldDelegate {

    /// Übernimmt den gemittelten Messpunkt in die Kennlinie
    var onAddPoint: ((SpeedPoint) -> Void)?

    private let loco: Locomotive
    private let client = Z21Client.shared
    private let settings = AppSettings.shared

    private var step: Int
    private var forward = true
    private var isDriving = false
    /// Gemessene Zeiten (Sekunden) für die aktuelle Fahrstufe
    private var runs: [Double] = []
    private var startTime: CFTimeInterval?
    private var displayLink: CADisplayLink?

    private let scroll = UIScrollView()
    private let trackPanel = PanelView(title: "1  Messstrecke")
    private let locoPanel = PanelView(title: "2  Lok fahren lassen")
    private let watchPanel = PanelView(title: "3  Zeit stoppen")

    private let scaleButton = ECoSButton(title: nil, style: .normal)
    private let distanceField = UITextField()
    private let distanceLabel = UILabel()
    private let hintLabel = UILabel()

    private let stepLabel = UILabel()
    private let minusButton = ECoSButton(title: "−", style: .normal)
    private let plusButton = ECoSButton(title: "+", style: .normal)
    private let reverseButton = ECoSButton(title: "◀", style: .normal)
    private let forwardButton = ECoSButton(title: "▶", style: .normal)
    private let driveButton = ECoSButton(title: "Lok fahren", style: .green)
    private let stopButton = ECoSButton(title: "Lok anhalten", style: .red)
    private let connectionLabel = UILabel()

    private let timeLabel = UILabel()
    private let resultLabel = UILabel()
    private let watchButton = ECoSButton(title: "START", style: .accent)
    private let resetButton = ECoSButton(title: "Abbrechen", style: .normal)
    private let runsLabel = UILabel()
    private let takeButton = ECoSButton(title: "Als Messpunkt übernehmen", style: .green)
    private let clearRunsButton = ECoSButton(title: "Läufe löschen", style: .normal)

    init(loco: Locomotive) {
        self.loco = loco
        self.step = max(1, loco.speedSteps.maxStep / 2)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        displayLink?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Einmessen: \(loco.name)"
        view.backgroundColor = Theme.background
        view.addSubview(scroll)
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        ([trackPanel, locoPanel, watchPanel] as [UIView]).forEach { scroll.addSubview($0) }

        // Messstrecke
        scaleButton.titleLabel?.font = Theme.font(16, bold: true)
        scaleButton.addTarget(self, action: #selector(chooseScale), for: .touchUpInside)
        distanceLabel.text = "Strecke in cm"
        distanceLabel.font = Theme.font(14, bold: true)
        distanceLabel.textColor = Theme.textDim
        distanceField.backgroundColor = Theme.inset
        distanceField.textColor = Theme.text
        distanceField.font = Theme.monoFont(22, bold: true)
        distanceField.textAlignment = .center
        distanceField.keyboardType = .decimalPad
        distanceField.keyboardAppearance = .light
        distanceField.layer.cornerRadius = 4
        distanceField.layer.borderWidth = 1
        distanceField.layer.borderColor = Theme.panelBorder.cgColor
        distanceField.delegate = self
        distanceField.text = SpeedFormat.number(settings.measureDistanceCm, digits: 0)
        distanceField.addTarget(self, action: #selector(distanceChanged), for: .editingChanged)
        hintLabel.text = "Zwei Marken im Abstand der Strecke an ein gerades Gleis kleben. "
            + "Die Lok braucht vor der ersten Marke etwas Anlauf, damit sie die Fahrstufe erreicht hat."
        hintLabel.font = Theme.font(13)
        hintLabel.textColor = Theme.textDim
        hintLabel.numberOfLines = 0
        ([scaleButton, distanceLabel, distanceField, hintLabel] as [UIView]).forEach { trackPanel.contentView.addSubview($0) }

        // Lok
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

        // Stoppuhr
        timeLabel.font = Theme.monoFont(48, bold: true)
        timeLabel.textColor = Theme.text
        timeLabel.textAlignment = .center
        resultLabel.font = Theme.font(17, bold: true)
        resultLabel.textColor = Theme.accent
        resultLabel.textAlignment = .center
        watchButton.titleLabel?.font = Theme.font(28, bold: true)
        watchButton.addTarget(self, action: #selector(watchTapped), for: .touchDown)
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        runsLabel.font = UIFont(name: "Menlo", size: 14) ?? Theme.font(14)
        runsLabel.textColor = Theme.text
        runsLabel.numberOfLines = 0
        takeButton.addTarget(self, action: #selector(takeTapped), for: .touchUpInside)
        clearRunsButton.addTarget(self, action: #selector(clearRunsTapped), for: .touchUpInside)
        ([timeLabel, resultLabel, watchButton, resetButton, runsLabel, takeButton, clearRunsButton] as [UIView])
            .forEach { watchPanel.contentView.addSubview($0) }

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        updateAll()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimer()
        if isDriving {
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
        scaleButton.frame = CGRect(x: 12, y: 30, width: half, height: 52)
        distanceLabel.frame = CGRect(x: 24 + half, y: 8, width: half, height: 20)
        distanceField.frame = CGRect(x: 24 + half, y: 30, width: half, height: 52)
        let hintH = hintLabel.sizeThatFits(CGSize(width: inner, height: 200)).height
        hintLabel.frame = CGRect(x: 12, y: 92, width: inner, height: hintH)
        trackPanel.frame = CGRect(x: pad, y: pad, width: w, height: PanelView.titleHeight + 92 + hintH + 12)

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

        // 3 Stoppuhr
        timeLabel.frame = CGRect(x: 12, y: 8, width: inner, height: 60)
        resultLabel.frame = CGRect(x: 12, y: 68, width: inner, height: 24)
        let resetW: CGFloat = 130
        watchButton.frame = CGRect(x: 12, y: 100, width: inner - resetW - 12, height: 96)
        resetButton.frame = CGRect(x: inner - resetW + 12, y: 100, width: resetW, height: 96)
        let runsH = runsLabel.sizeThatFits(CGSize(width: inner, height: 1000)).height
        runsLabel.frame = CGRect(x: 12, y: 208, width: inner, height: runsH)
        let by = 208 + runsH + 12
        takeButton.frame = CGRect(x: 12, y: by, width: inner - 160 - 12, height: 52)
        clearRunsButton.frame = CGRect(x: inner - 160 + 12, y: by, width: 160, height: 52)
        watchPanel.frame = CGRect(x: pad, y: locoPanel.frame.maxY + pad, width: w,
                                  height: PanelView.titleHeight + by + 52 + 12)

        scroll.contentSize = CGSize(width: view.bounds.width, height: watchPanel.frame.maxY + pad)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: Anzeige

    private var distanceCm: Double? {
        guard let d = SpeedFormat.parse(distanceField.text ?? ""), d > 0 else { return nil }
        return d
    }

    private var averageSeconds: Double? {
        guard !runs.isEmpty else { return nil }
        return runs.reduce(0, +) / Double(runs.count)
    }

    private func speed(forSeconds s: Double) -> Double? {
        guard let d = distanceCm else { return nil }
        return settings.modelScale.scaleSpeed(distanceCm: d, seconds: s)
    }

    private func updateAll() {
        scaleButton.setTitle("Maßstab: \(settings.modelScale.title)", for: .normal)
        stepLabel.text = "FS \(step)/\(loco.speedSteps.maxStep)"
        forwardButton.isOn = forward
        reverseButton.isOn = !forward
        minusButton.isEnabled = step > 1
        plusButton.isEnabled = step < loco.speedSteps.maxStep
        let connected = client.connectionState == .connected
        driveButton.isEnabled = connected
        stopButton.isEnabled = connected
        driveButton.markColor = isDriving ? Theme.text : nil
        connectionLabel.text = connected ? nil
            : "Nicht mit der Z21 verbunden. Die Lok kann auch mit einem anderen Regler fahren, die Zeit wird hier gestoppt."

        let running = startTime != nil
        watchButton.setTitle(running ? "ZIEL" : "START", for: .normal)
        watchButton.style = running ? .red : .accent
        resetButton.isEnabled = running
        if !running {
            timeLabel.text = runs.last.map { SpeedFormat.number($0, digits: 2) + " s" } ?? "0,00 s"
        }
        if let last = runs.last, let v = speed(forSeconds: last) {
            resultLabel.text = "Letzter Lauf: " + SpeedFormat.kmh(v)
        } else {
            resultLabel.text = distanceCm == nil ? "Bitte Strecke eingeben" : " "
        }

        if runs.isEmpty {
            runsLabel.text = "Noch keine Läufe bei Fahrstufe \(step). Tipp: Hin- und Rückfahrt messen und mitteln."
            runsLabel.textColor = Theme.textDim
        } else {
            var lines: [String] = []
            for (i, s) in runs.enumerated() {
                let v = speed(forSeconds: s).map { SpeedFormat.kmh($0) } ?? "–"
                lines.append("Lauf \(i + 1):  \(SpeedFormat.number(s, digits: 2)) s  →  \(v)")
            }
            if let avg = averageSeconds, let v = speed(forSeconds: avg) {
                lines.append("Mittelwert:  \(SpeedFormat.number(avg, digits: 2)) s  →  \(SpeedFormat.kmh(v))")
            }
            runsLabel.text = lines.joined(separator: "\n")
            runsLabel.textColor = Theme.text
        }
        let canTake = averageSeconds.flatMap { speed(forSeconds: $0) } != nil
        takeButton.isEnabled = canTake
        takeButton.setTitle("Fahrstufe \(step) als Messpunkt übernehmen", for: .normal)
        clearRunsButton.isEnabled = !runs.isEmpty
        view.setNeedsLayout()
    }

    // MARK: Messstrecke

    @objc private func chooseScale() {
        let sheet = UIAlertController(title: "Maßstab der Anlage", message: nil, preferredStyle: .actionSheet)
        for scale in ModelScale.allCases {
            let title = scale == settings.modelScale ? "✓ " + scale.title : scale.title
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.settings.modelScale = scale
                self?.updateAll()
            })
        }
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = scaleButton
        sheet.popoverPresentationController?.sourceRect = scaleButton.bounds
        present(sheet, animated: true, completion: nil)
    }

    @objc private func distanceChanged() {
        if let d = distanceCm {
            settings.measureDistanceCm = d
        }
        updateAll()
    }

    // MARK: Lok

    private func setStep(_ newStep: Int) {
        let clamped = max(1, min(newStep, loco.speedSteps.maxStep))
        guard clamped != step else { return }
        step = clamped
        runs = []           // Läufe gehören immer zu einer Fahrstufe
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
        sendDrive()
        updateAll()
    }

    @objc private func stopTapped() {
        client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: 0, forward: forward)
        isDriving = false
        updateAll()
    }

    // MARK: Stoppuhr

    @objc private func watchTapped() {
        view.endEditing(true)
        let now = CACurrentMediaTime()
        if let start = startTime {
            let seconds = now - start
            stopTimer()
            if seconds > 0.2 {
                runs.append(seconds)
            }
        } else {
            startTime = now
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        updateAll()
    }

    @objc private func tick() {
        guard let start = startTime else { return }
        timeLabel.text = SpeedFormat.number(CACurrentMediaTime() - start, digits: 2) + " s"
    }

    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
        startTime = nil
    }

    @objc private func resetTapped() {
        stopTimer()
        updateAll()
    }

    @objc private func clearRunsTapped() {
        runs = []
        updateAll()
    }

    @objc private func takeTapped() {
        guard let avg = averageSeconds, let kmh = speed(forSeconds: avg) else { return }
        onAddPoint?(SpeedPoint(step: step, maxStep: loco.speedSteps.maxStep, kmh: kmh))
        let count = runs.count
        runs = []
        updateAll()
        resultLabel.text = "Fahrstufe \(step) = \(SpeedFormat.kmh(kmh)) übernommen (\(count) Läufe)"
        resultLabel.textColor = Theme.green
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.resultLabel.textColor = Theme.accent
        }
    }
}
