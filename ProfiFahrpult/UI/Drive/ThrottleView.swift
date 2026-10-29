import UIKit

/// Ein Fahrregler im Stil der ECoS: Lokname in der Titelleiste, darunter Lokbild,
/// Tacho-Drehregler, Richtung und Funktionstasten. Passt auch in die schmale Spalte am Bildschirmrand.
final class ThrottleView: PanelView, Z21ClientObserver {

    let index: Int
    private(set) var loco: Locomotive?

    /// Wird aufgerufen, wenn der Benutzer eine andere Lok wählen möchte
    var onSelectLoco: ((ThrottleView, UIView) -> Void)?

    private let client = Z21Client.shared

    private let locoImage = LocoImageView()
    private let infoLabel = UILabel()
    private let busyLabel = UILabel()
    private let selectButton = ECoSButton(title: "Lok wählen", style: .accent)
    private let tacho = TachometerView()
    private let reverseButton = ECoSButton(title: "◀", style: .normal)
    private let forwardButton = ECoSButton(title: "▶", style: .normal)
    private let minusButton = ECoSButton(title: "−", style: .normal)
    private let plusButton = ECoSButton(title: "+", style: .normal)
    private let haltButton = ECoSButton(title: "HALT", style: .red)
    private var functionKeys: [FunctionKey] = []
    private var pageButtons: [ECoSButton] = []
    private let separator = UIView()

    private static let keysPerPage = 12
    private static let pages = [(0, 11), (12, 23), (24, 31)]
    private var functionPage = 0
    /// Eingehende Fahrstufen werden kurz nach einer Bedienung ignoriert, damit der Zeiger nicht springt
    private var lastUserSpeedChange = Date.distantPast

    init(index: Int) {
        self.index = index
        super.init(title: "Fahrregler \(index + 1)")
        titleLabel.font = Theme.font(17, bold: true)
        setupViews()
        client.addObserver(self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        client.removeObserver(self)
    }

    // MARK: Aufbau

    private func setupViews() {
        infoLabel.font = Theme.font(13)
        infoLabel.textColor = Theme.textDim
        infoLabel.adjustsFontSizeToFitWidth = true
        infoLabel.minimumScaleFactor = 0.7
        busyLabel.font = Theme.font(12, bold: true)
        busyLabel.textColor = Theme.functionOn
        busyLabel.text = "Wird von anderem Gerät gesteuert"
        busyLabel.isHidden = true
        separator.backgroundColor = Theme.panelBorder

        ([locoImage, infoLabel, busyLabel, selectButton, tacho,
          reverseButton, minusButton, haltButton, plusButton, forwardButton, separator] as [UIView]).forEach {
            contentView.addSubview($0)
        }

        selectButton.titleLabel?.font = Theme.font(14, bold: true)
        selectButton.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(selectTapped))
        locoImage.addGestureRecognizer(imageTap)

        tacho.addTarget(self, action: #selector(tachoChanged), for: .valueChanged)
        tacho.addTarget(self, action: #selector(tachoEnded), for: .editingDidEnd)

        for b in [reverseButton, forwardButton] {
            b.titleLabel?.font = Theme.font(24, bold: true)
            b.onColor = Theme.accent
        }
        for b in [minusButton, plusButton] {
            b.titleLabel?.font = Theme.font(28, bold: true)
        }
        haltButton.titleLabel?.font = Theme.font(18, bold: true)
        reverseButton.addTarget(self, action: #selector(reverseTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        minusButton.addTarget(self, action: #selector(minusTapped), for: .touchUpInside)
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        haltButton.addTarget(self, action: #selector(haltTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(haltLongPressed(_:)))
        longPress.minimumPressDuration = 0.6
        haltButton.addGestureRecognizer(longPress)

        for i in 0..<ThrottleView.keysPerPage {
            let key = FunctionKey(frame: .zero)
            key.tag = i
            key.addTarget(self, action: #selector(functionDown(_:)), for: .touchDown)
            key.addTarget(self, action: #selector(functionUpInside(_:)), for: .touchUpInside)
            key.addTarget(self, action: #selector(functionReleased(_:)), for: [.touchUpOutside, .touchCancel])
            contentView.addSubview(key)
            functionKeys.append(key)
        }
        for (i, page) in ThrottleView.pages.enumerated() {
            let b = ECoSButton(title: "F\(page.0)–F\(page.1)", style: .normal)
            b.titleLabel?.font = Theme.font(13, bold: true)
            b.onColor = Theme.accent
            b.tag = i
            b.addTarget(self, action: #selector(pageTapped(_:)), for: .touchUpInside)
            contentView.addSubview(b)
            pageButtons.append(b)
        }
        setLoco(nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        let pad: CGFloat = 10
        let gap: CGFloat = 8

        // Kopfzeile: Lokbild und Auswahl, darunter Adresse und Hinweise
        let headerH: CGFloat = 56
        let selW = min(120, max(70, floor(w * 0.26)))
        selectButton.frame = CGRect(x: w - pad - selW, y: pad, width: selW, height: headerH)
        locoImage.frame = CGRect(x: pad, y: pad, width: selectButton.frame.minX - gap - pad, height: headerH)
        infoLabel.frame = CGRect(x: pad, y: locoImage.frame.maxY + 4, width: w - 2 * pad, height: 18)
        busyLabel.frame = CGRect(x: pad, y: infoLabel.frame.maxY, width: w - 2 * pad, height: 16)

        // Funktionstasten unten
        let cols: CGFloat = 4
        let keyW = floor((w - 2 * pad - (cols - 1) * gap) / cols)
        let keyH = max(44, min(58, floor(keyW * 0.6)))
        let pageH: CGFloat = 36
        let rows: CGFloat = 3
        let fnHeight = rows * keyH + (rows - 1) * gap + gap + pageH
        let fnTop = h - pad - fnHeight
        for (i, key) in functionKeys.enumerated() {
            let col = CGFloat(i % 4)
            let row = CGFloat(i / 4)
            key.frame = CGRect(x: pad + col * (keyW + gap), y: fnTop + row * (keyH + gap), width: keyW, height: keyH)
        }
        let pageW = floor((w - 2 * pad - 2 * gap) / 3)
        for (i, b) in pageButtons.enumerated() {
            b.frame = CGRect(x: pad + CGFloat(i) * (pageW + gap), y: h - pad - pageH, width: pageW, height: pageH)
        }
        separator.frame = CGRect(x: pad, y: fnTop - gap, width: w - 2 * pad, height: 1)

        // Bedienzeile über den Funktionen
        let ctrlH: CGFloat = 52
        let ctrlTop = fnTop - 2 * gap - ctrlH
        let smallW = floor((w - 2 * pad - 4 * gap) / 5)
        let haltW = w - 2 * pad - 4 * gap - 4 * smallW
        var x = pad
        for b in [reverseButton, minusButton] {
            b.frame = CGRect(x: x, y: ctrlTop, width: smallW, height: ctrlH)
            x += smallW + gap
        }
        haltButton.frame = CGRect(x: x, y: ctrlTop, width: haltW, height: ctrlH)
        x += haltW + gap
        for b in [plusButton, forwardButton] {
            b.frame = CGRect(x: x, y: ctrlTop, width: smallW, height: ctrlH)
            x += smallW + gap
        }

        // Tacho füllt den Rest
        let tachoTop = busyLabel.frame.maxY + 2
        let avail = max(80, ctrlTop - gap - tachoTop)
        let size = min(w - 2 * pad, avail)
        tacho.frame = CGRect(x: (w - size) / 2, y: tachoTop + (avail - size) / 2, width: size, height: size)
    }

    // MARK: Lok

    func setLoco(_ loco: Locomotive?) {
        self.loco = loco
        let active = loco != nil
        title = loco.map { "\(index + 1) · \($0.name)" } ?? "Fahrregler \(index + 1) – keine Lok"
        locoImage.image = loco.flatMap { LocoStore.shared.image(for: $0) }
        locoImage.isDimmed = !active
        tacho.maxSpeedKmh = loco?.maxSpeedKmh ?? 120
        tacho.maxStep = (loco?.speedSteps ?? .steps128).maxStep
        tacho.speedCurve = loco?.speedCurve
        tacho.isActive = active
        tacho.isEnabled = active
        [reverseButton, forwardButton, minusButton, plusButton, haltButton].forEach { $0.isEnabled = active }
        functionKeys.forEach { $0.isEnabled = active }
        if let loco = loco {
            client.subscribeLoco(loco.address)
        } else {
            tacho.step = 0
        }
        updateInfoLabel()
        updateFromClient(force: true)
    }

    private var currentInfo: LocoInfo? {
        guard let loco = loco else { return nil }
        return client.locoInfo(loco.address)
    }

    private func updateInfoLabel() {
        guard let loco = loco else {
            infoLabel.text = "Tippen Sie auf „Lok wählen“"
            return
        }
        var text = "Adresse \(loco.address) · \(loco.speedSteps.title)"
        if let rc = client.railCom[loco.address], rc.speed > 0 {
            text += " · RailCom \(rc.speed) km/h"
        }
        infoLabel.text = text
    }

    private func updateFromClient(force: Bool = false) {
        let info = currentInfo
        let isForward = info?.forward ?? true
        let userIsDriving = tacho.isTracking || Date().timeIntervalSince(lastUserSpeedChange) < 0.6
        if force || !userIsDriving {
            tacho.step = info?.step ?? 0
            tacho.forward = isForward
            tacho.emergencyStop = info?.emergencyStop ?? false
        }
        forwardButton.isOn = loco != nil && isForward
        reverseButton.isOn = loco != nil && !isForward
        busyLabel.isHidden = !(info?.busy ?? false)
        updateFunctionKeys()
    }

    private func updateFunctionKeys() {
        let page = ThrottleView.pages[functionPage]
        for (i, key) in functionKeys.enumerated() {
            let fn = page.0 + i
            if fn > page.1 {
                key.isHidden = true
                continue
            }
            key.isHidden = false
            let function = loco?.function(fn) ?? LocoFunction(index: fn, name: "", icon: .generic, momentary: false)
            key.configure(function, on: currentInfo?.isFunctionOn(fn) ?? false)
        }
        for (i, b) in pageButtons.enumerated() {
            b.isOn = i == functionPage
        }
    }

    // MARK: Bedienung

    private func drive(step: Int, forward: Bool) {
        guard let loco = loco else { return }
        lastUserSpeedChange = Date()
        let clamped = max(0, min(step, loco.speedSteps.maxStep))
        client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: clamped, forward: forward)
        tacho.step = clamped
        tacho.forward = forward
        tacho.emergencyStop = false
        forwardButton.isOn = forward
        reverseButton.isOn = !forward
    }

    @objc private func selectTapped() {
        onSelectLoco?(self, selectButton)
    }

    @objc private func tachoChanged() {
        drive(step: tacho.step, forward: tacho.forward)
    }

    @objc private func tachoEnded() {
        lastUserSpeedChange = Date()
    }

    private func changeDirection(forward: Bool) {
        guard loco != nil else { return }
        let current = tacho.forward
        if current == forward {
            // erneutes Drücken der aktiven Richtung sendet den Zustand nochmals
            drive(step: tacho.step, forward: forward)
            return
        }
        let step = AppSettings.shared.directionChangeStops ? 0 : tacho.step
        drive(step: step, forward: forward)
    }

    @objc private func reverseTapped() { changeDirection(forward: false) }
    @objc private func forwardTapped() { changeDirection(forward: true) }

    @objc private func minusTapped() {
        drive(step: tacho.step - 1, forward: tacho.forward)
    }

    @objc private func plusTapped() {
        drive(step: tacho.step + 1, forward: tacho.forward)
    }

    @objc private func haltTapped() {
        drive(step: 0, forward: tacho.forward)
    }

    @objc private func haltLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let loco = loco else { return }
        lastUserSpeedChange = Date()
        client.emergencyStopLoco(loco.address)
        tacho.step = 0
        tacho.emergencyStop = true
    }

    @objc private func pageTapped(_ sender: ECoSButton) {
        functionPage = sender.tag
        updateFunctionKeys()
    }

    private func functionIndex(for key: FunctionKey) -> Int {
        return ThrottleView.pages[functionPage].0 + key.tag
    }

    @objc private func functionDown(_ key: FunctionKey) {
        guard let loco = loco else { return }
        let fn = functionIndex(for: key)
        if loco.function(fn).momentary {
            client.setLocoFunction(address: loco.address, function: fn, on: true)
        }
    }

    @objc private func functionUpInside(_ key: FunctionKey) {
        guard let loco = loco else { return }
        let fn = functionIndex(for: key)
        if loco.function(fn).momentary {
            client.setLocoFunction(address: loco.address, function: fn, on: false)
        } else {
            let on = currentInfo?.isFunctionOn(fn) ?? false
            client.setLocoFunction(address: loco.address, function: fn, on: !on)
        }
    }

    /// Finger außerhalb der Taste losgelassen: nur Moment-Funktionen wieder ausschalten
    @objc private func functionReleased(_ key: FunctionKey) {
        guard let loco = loco else { return }
        let fn = functionIndex(for: key)
        if loco.function(fn).momentary {
            client.setLocoFunction(address: loco.address, function: fn, on: false)
        }
    }

    // MARK: Z21ClientObserver

    func z21Client(_ client: Z21Client, locoChanged info: LocoInfo) {
        guard let loco = loco, info.address == loco.address else { return }
        updateFromClient()
    }

    func z21Client(_ client: Z21Client, railCom data: RailComData) {
        guard let loco = loco, data.address == loco.address else { return }
        updateInfoLabel()
    }

    func z21ClientConnectionChanged(_ client: Z21Client) {
        if client.connectionState == .connected, let loco = loco {
            client.subscribeLoco(loco.address)
        }
    }
}
