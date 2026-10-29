import UIKit

/// CV-Programmierung auf dem Programmiergleis (Service-Modus) und dem Hauptgleis (POM)
final class ProgramViewController: UIViewController, UITextFieldDelegate, Z21ClientObserver {

    private let client = Z21Client.shared

    private let cvPanel = PanelView(title: "CV lesen / schreiben")
    private let addressPanel = PanelView(title: "Lokadresse (Programmiergleis)")
    private let logPanel = PanelView(title: "Protokoll")

    private let modeControl = UISegmentedControl(items: ["Programmiergleis", "Hauptgleis (POM)"])
    private let locoAddressField = ProgramViewController.makeField(placeholder: "Lokadresse")
    private let cvField = ProgramViewController.makeField(placeholder: "CV")
    private let valueField = ProgramViewController.makeField(placeholder: "Wert")
    private let locoAddressLabel = ProgramViewController.makeLabel("Lokadresse")
    private let cvLabel = ProgramViewController.makeLabel("CV-Nummer")
    private let valueLabel = ProgramViewController.makeLabel("Wert (0–255)")
    private var bitButtons: [ECoSButton] = []
    private let readButton = ECoSButton(title: "Lesen", style: .accent)
    private let writeButton = ECoSButton(title: "Schreiben", style: .red)

    private let newAddressField = ProgramViewController.makeField(placeholder: "Neue Adresse")
    private let readAddressButton = ECoSButton(title: "Adresse lesen", style: .accent)
    private let writeAddressButton = ECoSButton(title: "Adresse schreiben", style: .red)
    private let leaveProgButton = ECoSButton(title: "Programmiermodus beenden", style: .green)
    private let busyIndicator = UIActivityIndicatorView(style: .whiteLarge)

    private let logView = UITextView()

    private var isPOM: Bool { return modeControl.selectedSegmentIndex == 1 }

    static func makeField(placeholder: String) -> UITextField {
        let tf = UITextField()
        tf.backgroundColor = Theme.inset
        tf.textColor = Theme.text
        tf.font = Theme.monoFont(24, bold: true)
        tf.textAlignment = .center
        tf.keyboardType = .numberPad
        tf.keyboardAppearance = .light
        tf.layer.cornerRadius = 4
        tf.layer.borderColor = Theme.panelBorder.cgColor
        tf.layer.borderWidth = 1
        tf.attributedPlaceholder = NSAttributedString(string: placeholder,
                                                      attributes: [.foregroundColor: Theme.textDark])
        return tf
    }

    static func makeLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = Theme.font(14, bold: true)
        l.textColor = Theme.textDim
        return l
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        [cvPanel, addressPanel, logPanel].forEach { view.addSubview($0) }

        modeControl.selectedSegmentIndex = 0
        modeControl.tintColor = Theme.accent
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        ([modeControl, locoAddressLabel, locoAddressField, cvLabel, cvField, valueLabel, valueField,
          readButton, writeButton] as [UIView]).forEach { cvPanel.contentView.addSubview($0) }
        for bit in (0..<8).reversed() {
            let b = ECoSButton(title: "\(bit)", style: .normal)
            b.tag = bit
            b.addTarget(self, action: #selector(bitTapped(_:)), for: .touchUpInside)
            cvPanel.contentView.addSubview(b)
            bitButtons.append(b)
        }
        [cvField, valueField, locoAddressField, newAddressField].forEach { $0.delegate = self }
        valueField.addTarget(self, action: #selector(valueEdited), for: .editingChanged)
        cvField.text = "1"
        valueField.text = "3"
        valueEdited()

        readButton.addTarget(self, action: #selector(readTapped), for: .touchUpInside)
        writeButton.addTarget(self, action: #selector(writeTapped), for: .touchUpInside)

        ([newAddressField, readAddressButton, writeAddressButton, leaveProgButton, busyIndicator] as [UIView]).forEach {
            addressPanel.contentView.addSubview($0)
        }
        readAddressButton.addTarget(self, action: #selector(readAddressTapped), for: .touchUpInside)
        writeAddressButton.addTarget(self, action: #selector(writeAddressTapped), for: .touchUpInside)
        leaveProgButton.addTarget(self, action: #selector(leaveProgTapped), for: .touchUpInside)
        busyIndicator.hidesWhenStopped = true

        logView.backgroundColor = Theme.inset
        logView.textColor = Theme.text
        logView.font = UIFont(name: "Menlo", size: 14) ?? Theme.font(14)
        logView.isEditable = false
        logView.layer.cornerRadius = 4
        logPanel.contentView.addSubview(logView)

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        modeChanged()
        client.addObserver(self)
        log("Hinweis: Lesen/Schreiben auf dem Programmiergleis versetzt die Z21 in den Programmiermodus.")
    }

    deinit {
        client.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let pad: CGFloat = 8
        let w = view.bounds.width
        let h = view.bounds.height
        let leftW = min(560, floor(w * 0.58))
        cvPanel.frame = CGRect(x: pad, y: pad, width: leftW - pad, height: 380)
        addressPanel.frame = CGRect(x: pad, y: cvPanel.frame.maxY + pad, width: leftW - pad, height: 190)
        logPanel.frame = CGRect(x: leftW + pad, y: pad, width: w - leftW - 2 * pad, height: h - 2 * pad)
        if w < 700 {
            // Hochformat: Protokoll unten
            cvPanel.frame = CGRect(x: pad, y: pad, width: w - 2 * pad, height: 380)
            addressPanel.frame = CGRect(x: pad, y: cvPanel.frame.maxY + pad, width: w - 2 * pad, height: 190)
            logPanel.frame = CGRect(x: pad, y: addressPanel.frame.maxY + pad, width: w - 2 * pad,
                                    height: max(120, h - addressPanel.frame.maxY - 2 * pad))
        }
        [cvPanel, addressPanel, logPanel].forEach { $0.layoutIfNeeded() }

        let cw = cvPanel.contentView.bounds.width
        let inner = cw - 24
        modeControl.frame = CGRect(x: 12, y: 12, width: inner, height: 36)
        let colW = floor((inner - 24) / 3)
        let labels = [locoAddressLabel, cvLabel, valueLabel]
        let fields = [locoAddressField, cvField, valueField]
        for i in 0..<3 {
            let x = 12 + CGFloat(i) * (colW + 12)
            labels[i].frame = CGRect(x: x, y: 60, width: colW, height: 20)
            fields[i].frame = CGRect(x: x, y: 82, width: colW, height: 52)
        }
        let bitW = floor((inner - 7 * 6) / 8)
        for (i, b) in bitButtons.enumerated() {
            b.frame = CGRect(x: 12 + CGFloat(i) * (bitW + 6), y: 160, width: bitW, height: 46)
        }
        let btnW = floor((inner - 12) / 2)
        readButton.frame = CGRect(x: 12, y: 226, width: btnW, height: 56)
        writeButton.frame = CGRect(x: 24 + btnW, y: 226, width: btnW, height: 56)

        let aw = addressPanel.contentView.bounds.width - 24
        let third = floor((aw - 24) / 3)
        newAddressField.frame = CGRect(x: 12, y: 12, width: third, height: 52)
        readAddressButton.frame = CGRect(x: 24 + third, y: 12, width: third, height: 52)
        writeAddressButton.frame = CGRect(x: 36 + 2 * third, y: 12, width: third, height: 52)
        leaveProgButton.frame = CGRect(x: 12, y: 80, width: aw - 60, height: 52)
        busyIndicator.center = CGPoint(x: leaveProgButton.frame.maxX + 30, y: leaveProgButton.frame.midY)

        logView.frame = logPanel.contentView.bounds.insetBy(dx: 8, dy: 8)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: Hilfen

    private func log(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(text)\n"
        logView.text = line + (logView.text ?? "")
    }

    private func setBusy(_ busy: Bool) {
        [readButton, writeButton, readAddressButton, writeAddressButton].forEach { $0.isEnabled = !busy }
        if busy { busyIndicator.startAnimating() } else { busyIndicator.stopAnimating() }
    }

    private func describe(_ result: CVResult) -> String {
        switch result {
        case .value(let v): return "\(v)"
        case .success: return "gesendet"
        case .noAcknowledge: return "keine Antwort vom Decoder"
        case .shortCircuit: return "Kurzschluss auf dem Programmiergleis"
        case .timeout: return "Zeitüberschreitung"
        case .notConnected: return "nicht mit der Z21 verbunden"
        }
    }

    private func parseCV() -> UInt16? {
        guard let cv = Int(cvField.text ?? ""), cv >= 1, cv <= 1024 else {
            showMessage("Ungültige CV-Nummer", "Erlaubt sind CV 1 bis 1024.")
            return nil
        }
        return UInt16(cv)
    }

    private func parseValue() -> UInt8? {
        guard let v = Int(valueField.text ?? ""), v >= 0, v <= 255 else {
            showMessage("Ungültiger Wert", "Erlaubt sind Werte von 0 bis 255.")
            return nil
        }
        return UInt8(v)
    }

    private func parseLocoAddress() -> UInt16? {
        guard let a = Int(locoAddressField.text ?? ""), a >= 1, a <= 9999 else {
            showMessage("Ungültige Lokadresse")
            return nil
        }
        return UInt16(a)
    }

    private func setValue(_ v: UInt8) {
        valueField.text = "\(v)"
        valueEdited()
    }

    @objc private func valueEdited() {
        let v = Int(valueField.text ?? "") ?? 0
        for b in bitButtons {
            b.isOn = (v >> b.tag) & 1 == 1
        }
    }

    @objc private func bitTapped(_ sender: ECoSButton) {
        var v = Int(valueField.text ?? "") ?? 0
        v = max(0, min(255, v)) ^ (1 << sender.tag)
        setValue(UInt8(v))
    }

    @objc private func modeChanged() {
        locoAddressField.isEnabled = isPOM
        locoAddressField.alpha = isPOM ? 1 : 0.35
        locoAddressLabel.alpha = locoAddressField.alpha
        if isPOM, (locoAddressField.text ?? "").isEmpty,
           let loco = LocoStore.shared.loco(id: AppSettings.shared.throttleLocoID(0)) {
            locoAddressField.text = "\(loco.address)"
        }
    }

    // MARK: CV

    @objc private func readTapped() {
        view.endEditing(true)
        guard let cv = parseCV() else { return }
        setBusy(true)
        let completion: (CVResult) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.setBusy(false)
            if case .value(let v) = result {
                self.setValue(v)
                self.log("CV\(cv) = \(v)  (0b\(self.binary(v)))")
            } else {
                self.log("CV\(cv) lesen: \(self.describe(result))")
            }
        }
        if isPOM {
            guard let addr = parseLocoAddress() else { setBusy(false); return }
            log("POM Lok \(addr): lese CV\(cv) …")
            client.readPOM(address: addr, cv: cv, completion: completion)
        } else {
            log("Programmiergleis: lese CV\(cv) …")
            client.readCV(cv, completion: completion)
        }
    }

    @objc private func writeTapped() {
        view.endEditing(true)
        guard let cv = parseCV(), let value = parseValue() else { return }
        if isPOM {
            guard let addr = parseLocoAddress() else { return }
            client.writePOM(address: addr, cv: cv, value: value) { [weak self] result in
                self?.log("POM Lok \(addr): CV\(cv) = \(value) – \(self?.describe(result) ?? "")")
            }
            return
        }
        setBusy(true)
        log("Programmiergleis: schreibe CV\(cv) = \(value) …")
        client.writeCV(cv, value: value) { [weak self] result in
            guard let self = self else { return }
            self.setBusy(false)
            if case .value(let v) = result {
                self.log(v == value ? "CV\(cv) = \(v) geschrieben ✓" : "CV\(cv): Rückmeldung \(v) weicht ab")
            } else {
                self.log("CV\(cv) schreiben: \(self.describe(result))")
            }
        }
    }

    private func binary(_ v: UInt8) -> String {
        let s = String(v, radix: 2)
        return String(repeating: "0", count: 8 - s.count) + s
    }

    // MARK: Adresse

    @objc private func readAddressTapped() {
        view.endEditing(true)
        setBusy(true)
        log("Lese Lokadresse (CV29) …")
        client.readCV(29) { [weak self] r29 in
            guard let self = self else { return }
            guard case .value(let cv29) = r29 else {
                self.setBusy(false)
                self.log("CV29 lesen: \(self.describe(r29))")
                return
            }
            if cv29 & 0x20 != 0 {
                self.client.readCV(17) { r17 in
                    guard case .value(let cv17) = r17 else {
                        self.setBusy(false)
                        self.log("CV17 lesen: \(self.describe(r17))")
                        return
                    }
                    self.client.readCV(18) { r18 in
                        self.setBusy(false)
                        guard case .value(let cv18) = r18 else {
                            self.log("CV18 lesen: \(self.describe(r18))")
                            return
                        }
                        let addr = (Int(cv17 & 0x3F) << 8) | Int(cv18)
                        self.newAddressField.text = "\(addr)"
                        self.log("Lange Adresse: \(addr) (CV17=\(cv17), CV18=\(cv18))")
                    }
                }
            } else {
                self.client.readCV(1) { r1 in
                    self.setBusy(false)
                    guard case .value(let cv1) = r1 else {
                        self.log("CV1 lesen: \(self.describe(r1))")
                        return
                    }
                    self.newAddressField.text = "\(cv1)"
                    self.log("Kurze Adresse: \(cv1)")
                }
            }
        }
    }

    @objc private func writeAddressTapped() {
        view.endEditing(true)
        guard let addr = Int(newAddressField.text ?? ""), addr >= 1, addr <= 9999 else {
            showMessage("Ungültige Adresse", "Erlaubt sind die Adressen 1 bis 9999.")
            return
        }
        setBusy(true)
        let fail: (String, CVResult) -> Void = { [weak self] step, result in
            guard let self = self else { return }
            self.setBusy(false)
            self.log("\(step): \(self.describe(result))")
        }
        client.readCV(29) { [weak self] r29 in
            guard let self = self else { return }
            guard case .value(let cv29) = r29 else { return fail("CV29 lesen", r29) }
            if addr <= 127 {
                self.client.writeCV(1, value: UInt8(addr)) { r1 in
                    guard case .value = r1 else { return fail("CV1 schreiben", r1) }
                    self.client.writeCV(29, value: cv29 & ~0x20) { r in
                        guard case .value = r else { return fail("CV29 schreiben", r) }
                        self.setBusy(false)
                        self.log("Kurze Adresse \(addr) geschrieben ✓")
                    }
                }
            } else {
                let cv17 = UInt8(0xC0 | ((addr >> 8) & 0x3F))
                let cv18 = UInt8(addr & 0xFF)
                self.client.writeCV(17, value: cv17) { r17 in
                    guard case .value = r17 else { return fail("CV17 schreiben", r17) }
                    self.client.writeCV(18, value: cv18) { r18 in
                        guard case .value = r18 else { return fail("CV18 schreiben", r18) }
                        self.client.writeCV(29, value: cv29 | 0x20) { r in
                            guard case .value = r else { return fail("CV29 schreiben", r) }
                            self.setBusy(false)
                            self.log("Lange Adresse \(addr) geschrieben ✓")
                        }
                    }
                }
            }
        }
    }

    @objc private func leaveProgTapped() {
        client.leaveProgrammingMode()
        log("Programmiermodus beendet, Gleisspannung eingeschaltet")
    }

    func z21ClientTrackStatusChanged(_ client: Z21Client) {
        if client.trackStatus == .shortCircuit {
            log("⚠︎ Kurzschluss gemeldet")
        }
    }
}
