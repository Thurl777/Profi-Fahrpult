import UIKit

/// Ein Fahrregler wie auf dem Display der ECoS: Lokname mit Unterstrich, darunter
/// Richtungstasten links/rechts neben dem Lokbild, der schwarze Tacho mit gelbem Zeiger,
/// optional ein Schieberegler an der Außenseite, Funktionstasten und unten die blaue
/// Tastenleiste mit Reglertausch, Lokeinstellungen und den Funktionsseiten.
final class ThrottleView: PanelView, Z21ClientObserver {

    let index: Int
    private(set) var loco: Locomotive?

    /// Wird aufgerufen, wenn der Benutzer eine andere Lok wählen möchte (Tippen auf das Lokbild)
    var onSelectLoco: ((ThrottleView, UIView) -> Void)?
    /// Loks der beiden Regler tauschen (falls die Multimaus-Kopplung den falschen Regler erwischt hat)
    var onSwap: (() -> Void)?
    /// Einstellungen der Lok dieses Reglers öffnen
    var onEditLoco: ((ThrottleView, Locomotive) -> Void)?
    /// Der Regler wurde in der App bedient
    var onUserActivity: ((ThrottleView) -> Void)?

    private let client = Z21Client.shared

    private let locoImage = LocoImageView()
    private let infoLabel = UILabel()
    private let busyLabel = UILabel()
    private let swapButton = ECoSButton(title: "⇄", style: .normal)
    private let settingsButton = ECoSButton(title: nil, style: .normal)
    private let tacho = TachometerView()
    private let fader = ThrottleFaderView()
    private let reverseButton = ECoSButton(title: "◀", style: .normal)
    private let forwardButton = ECoSButton(title: "▶", style: .normal)
    private var functionKeys: [FunctionKey] = []
    private var pageButtons: [ECoSButton] = []
    private let separator = UIView()
    private let bottomBar = UIView()

    private static let keysPerPage = 12
    private static let pages = [(0, 11), (12, 23), (24, 31)]
    private var functionPage = 0
    /// Eingehende Fahrstufen werden kurz nach einer Bedienung ignoriert, damit der Zeiger nicht springt
    private var lastUserSpeedChange = Date.distantPast
    /// So lange nach einer Bedienung am Handregler wird „Handregler aktiv“ angezeigt
    private static let handheldHintTime: TimeInterval = 5

    /// Der linke Regler hat den Schieberegler links vom Tacho, der rechte rechts davon
    private var faderOnLeft: Bool { return index % 2 == 0 }

    init(index: Int) {
        self.index = index
        super.init(title: "Fahrregler \(index + 1)")
        titleLabel.font = Theme.font(16, bold: true)
        setupViews()
        client.addObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(faderVisibilityChanged),
                                               name: .throttleFaderVisibilityChanged, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        client.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Aufbau

    private func setupViews() {
        infoLabel.font = Theme.font(13)
        infoLabel.textColor = Theme.textDim
        infoLabel.adjustsFontSizeToFitWidth = true
        infoLabel.minimumScaleFactor = 0.7
        busyLabel.font = Theme.font(12, bold: true)
        busyLabel.textColor = Theme.red
        busyLabel.isHidden = true
        separator.backgroundColor = Theme.panelBorder
        bottomBar.backgroundColor = Theme.bar

        ([bottomBar, locoImage, infoLabel, busyLabel, swapButton, settingsButton, tacho, fader,
          reverseButton, forwardButton, separator] as [UIView]).forEach {
            contentView.addSubview($0)
        }

        swapButton.titleLabel?.font = Theme.font(22, bold: true)
        swapButton.accessibilityLabel = "Regler tauschen"
        swapButton.addTarget(self, action: #selector(swapTapped), for: .touchUpInside)
        settingsButton.setImage(ThrottleView.wrenchIcon(size: 22, color: .white), for: .normal)
        settingsButton.accessibilityLabel = "Lokeinstellungen"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        let imageTap = UITapGestureRecognizer(target: self, action: #selector(selectTapped))
        locoImage.addGestureRecognizer(imageTap)

        tacho.addTarget(self, action: #selector(tachoChanged), for: .valueChanged)
        tacho.addTarget(self, action: #selector(tachoEnded), for: .editingDidEnd)
        // Ersatz für die frühere HALT-Taste: langes Drücken auf den Tacho = Nothalt dieser Lok
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tachoLongPressed(_:)))
        longPress.minimumPressDuration = 0.6
        tacho.addGestureRecognizer(longPress)

        fader.scaleSide = faderOnLeft ? .right : .left
        fader.addTarget(self, action: #selector(faderChanged), for: .valueChanged)
        fader.addTarget(self, action: #selector(tachoEnded), for: .editingDidEnd)
        fader.isHidden = !AppSettings.shared.showThrottleFader

        for b in [reverseButton, forwardButton] {
            b.titleLabel?.font = Theme.font(22, bold: true)
            b.onColor = Theme.functionOn
        }
        reverseButton.addTarget(self, action: #selector(reverseTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

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
            b.onColor = Theme.functionOn
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

        // Kopfzeile: ◀ Lokbild ▶, darunter Adresse und Hinweise
        let headerH: CGFloat = 46
        let dirW = min(70, max(50, floor(w * 0.17)))
        reverseButton.frame = CGRect(x: pad, y: pad, width: dirW, height: headerH)
        forwardButton.frame = CGRect(x: w - pad - dirW, y: pad, width: dirW, height: headerH)
        let imgX = reverseButton.frame.maxX + gap
        locoImage.frame = CGRect(x: imgX, y: pad, width: forwardButton.frame.minX - gap - imgX, height: headerH)
        infoLabel.frame = CGRect(x: pad, y: locoImage.frame.maxY + 4, width: w - 2 * pad, height: 18)
        busyLabel.frame = CGRect(x: pad, y: infoLabel.frame.maxY, width: w - 2 * pad, height: 16)

        // Blaue Tastenleiste unten: ⇄ (statt „Lok wählen“), Lokeinstellungen (statt ⇄) und Funktionsseiten
        let barH: CGFloat = 50
        bottomBar.frame = CGRect(x: 0, y: h - barH, width: w, height: barH)
        let smallW: CGFloat = 44
        let wideButtons = [swapButton] + pageButtons
        let bw = floor((w - 2 * pad - smallW - CGFloat(wideButtons.count) * gap) / CGFloat(wideButtons.count))
        var x = pad
        for b in [swapButton, settingsButton] + pageButtons {
            let bWidth = b === settingsButton ? smallW : bw
            b.frame = CGRect(x: x, y: h - barH + 7, width: bWidth, height: barH - 14)
            x += bWidth + gap
        }

        // Funktionstasten
        let cols: CGFloat = 4
        let keyW = floor((w - 2 * pad - (cols - 1) * gap) / cols)
        let keyH = max(44, min(52, floor(keyW * 0.6)))
        let rows: CGFloat = 3
        let fnTop = h - barH - pad - (rows * keyH + (rows - 1) * gap)
        for (i, key) in functionKeys.enumerated() {
            let col = CGFloat(i % 4)
            let row = CGFloat(i / 4)
            key.frame = CGRect(x: pad + col * (keyW + gap), y: fnTop + row * (keyH + gap), width: keyW, height: keyH)
        }
        separator.frame = CGRect(x: pad, y: fnTop - gap, width: w - 2 * pad, height: 1)

        // Tacho füllt den Platz der früheren − HALT + Zeile mit, der Schieberegler steht an der Außenseite
        let tachoTop = busyLabel.frame.maxY + 2
        let avail = max(80, separator.frame.minY - gap - tachoTop)
        let faderW: CGFloat = fader.isHidden ? 0 : 64
        let areaX = faderOnLeft ? pad + faderW : pad
        let areaW = w - 2 * pad - faderW
        let size = min(areaW, avail)
        tacho.frame = CGRect(x: areaX + (areaW - size) / 2, y: tachoTop + (avail - size) / 2, width: size, height: size)
        if !fader.isHidden {
            let fx = faderOnLeft ? pad : w - pad - faderW
            fader.frame = CGRect(x: fx, y: tacho.frame.minY, width: faderW, height: size)
        }
    }

    @objc private func faderVisibilityChanged() {
        fader.isHidden = !AppSettings.shared.showThrottleFader
        setNeedsLayout()
    }

    // MARK: Lok

    func setLoco(_ loco: Locomotive?) {
        self.loco = loco
        let active = loco != nil
        title = loco?.name ?? "Fahrregler \(index + 1) – keine Lok"
        locoImage.image = loco.flatMap { LocoStore.shared.image(for: $0) }
        locoImage.isDimmed = !active
        let maxStep = (loco?.speedSteps ?? .steps128).maxStep
        tacho.maxSpeedKmh = loco?.maxSpeedKmh ?? 120
        tacho.maxStep = maxStep
        tacho.addressText = loco.map { String(format: "[%04d]", Int($0.address)) }
        tacho.speedCurve = loco?.speedCurve
        tacho.isActive = active
        tacho.isEnabled = active
        fader.maxStep = maxStep
        fader.isActive = active
        fader.isEnabled = active
        [reverseButton, forwardButton, settingsButton].forEach { $0.isEnabled = active }
        functionKeys.forEach { $0.isEnabled = active }
        if let loco = loco {
            client.subscribeLoco(loco.address)
        } else {
            tacho.step = 0
            fader.step = 0
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
            infoLabel.text = "Zum Lok wählen auf das Lokbild tippen"
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
        let userIsDriving = tacho.isTracking || fader.isTracking || Date().timeIntervalSince(lastUserSpeedChange) < 0.6
        if force || !userIsDriving {
            tacho.step = info?.step ?? 0
            tacho.forward = isForward
            tacho.emergencyStop = info?.emergencyStop ?? false
            fader.step = tacho.step
        }
        forwardButton.isOn = loco != nil && isForward
        reverseButton.isOn = loco != nil && !isForward
        updateHint()
        updateFunctionKeys()
    }

    /// Hinweis unter dem Loknamen: von anderem X-Bus-Gerät belegt oder gerade am Handregler bedient
    private func updateHint() {
        if currentInfo?.busy ?? false {
            busyLabel.text = "Wird von anderem Gerät gesteuert"
        } else if let loco = loco, let last = client.lastExternalActivity[loco.address],
                  Date().timeIntervalSince(last) < ThrottleView.handheldHintTime {
            busyLabel.text = "Handregler aktiv"
        } else {
            busyLabel.text = nil
        }
        busyLabel.isHidden = busyLabel.text == nil
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
        onUserActivity?(self)
        let clamped = max(0, min(step, loco.speedSteps.maxStep))
        client.setLocoDrive(address: loco.address, speedSteps: loco.speedSteps, step: clamped, forward: forward)
        tacho.step = clamped
        tacho.forward = forward
        tacho.emergencyStop = false
        fader.step = clamped
        forwardButton.isOn = forward
        reverseButton.isOn = !forward
    }

    @objc private func selectTapped() {
        onSelectLoco?(self, locoImage)
    }

    @objc private func swapTapped() {
        onSwap?()
    }

    @objc private func settingsTapped() {
        guard let loco = loco else { return }
        onEditLoco?(self, loco)
    }

    @objc private func tachoChanged() {
        drive(step: tacho.step, forward: tacho.forward)
    }

    @objc private func faderChanged() {
        drive(step: fader.step, forward: tacho.forward)
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

    @objc private func tachoLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let loco = loco else { return }
        lastUserSpeedChange = Date()
        onUserActivity?(self)
        client.emergencyStopLoco(loco.address)
        tacho.step = 0
        tacho.emergencyStop = true
        fader.step = 0
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
        onUserActivity?(self)
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

    // MARK: Symbol

    /// Schraubenschlüssel wie auf der Einstellungstaste der ECoS
    static func wrenchIcon(size: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let ctx = context.cgContext
            ctx.translateBy(x: size / 2, y: size / 2)
            ctx.rotate(by: .pi / 4)
            color.setFill()
            let handle = UIBezierPath(roundedRect: CGRect(x: -size * 0.09, y: -size * 0.1, width: size * 0.18, height: size * 0.56),
                                      cornerRadius: size * 0.09)
            handle.fill()
            let headR = size * 0.22
            UIBezierPath(ovalIn: CGRect(x: -headR, y: -size * 0.24 - headR, width: headR * 2, height: headR * 2)).fill()
            // Maulöffnung ausstanzen
            ctx.setBlendMode(.clear)
            UIBezierPath(rect: CGRect(x: -size * 0.08, y: -size * 0.5, width: size * 0.16, height: size * 0.28)).fill()
        }
    }

    // MARK: Z21ClientObserver

    func z21Client(_ client: Z21Client, locoChanged info: LocoInfo) {
        guard let loco = loco, info.address == loco.address else { return }
        updateFromClient()
    }

    func z21Client(_ client: Z21Client, externalLocoActivity info: LocoInfo) {
        guard let loco = loco, info.address == loco.address else { return }
        updateHint()
        DispatchQueue.main.asyncAfter(deadline: .now() + ThrottleView.handheldHintTime + 0.1) { [weak self] in
            self?.updateHint()
        }
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
