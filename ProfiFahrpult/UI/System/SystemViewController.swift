import UIKit

/// Verbindung, Informationen zur Zentrale, Systemzustand und Einstellungen
final class SystemViewController: UITableViewController, UITextFieldDelegate, Z21ClientObserver {

    private let client = Z21Client.shared
    private let settings = AppSettings.shared

    private let hostField = UITextField()
    private let portField = UITextField()
    private let stopModeControl = UISegmentedControl(items: ["Gleisspannung aus", "Nothalt aller Loks"])
    private let directionSwitch = UISwitch()
    private let screenSwitch = UISwitch()
    private let autoConnectSwitch = UISwitch()
    private let turnoutStepper = UIStepper()

    private enum Section: Int, CaseIterable {
        case connection
        case station
        case state
        case settings
    }

    init() {
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = Theme.background
        for tf in [hostField, portField] {
            tf.textColor = Theme.text
            tf.font = Theme.monoFont(17)
            tf.textAlignment = .right
            tf.keyboardType = .numbersAndPunctuation
            tf.keyboardAppearance = .dark
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
            tf.delegate = self
        }
        hostField.text = settings.host
        portField.text = "\(settings.port)"
        portField.keyboardType = .numberPad

        stopModeControl.selectedSegmentIndex = settings.stopButtonMode.rawValue
        stopModeControl.tintColor = Theme.accent
        stopModeControl.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)
        directionSwitch.isOn = settings.directionChangeStops
        screenSwitch.isOn = settings.keepScreenOn
        autoConnectSwitch.isOn = settings.autoConnect
        for s in [directionSwitch, screenSwitch, autoConnectSwitch] {
            s.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)
        }
        turnoutStepper.minimumValue = 50
        turnoutStepper.maximumValue = 1000
        turnoutStepper.stepValue = 50
        turnoutStepper.value = Double(settings.turnoutSwitchTime)
        turnoutStepper.tintColor = Theme.accent
        turnoutStepper.addTarget(self, action: #selector(settingsChanged), for: .valueChanged)

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        client.addObserver(self)
    }

    deinit {
        client.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc private func settingsChanged() {
        settings.stopButtonMode = StopButtonMode(rawValue: stopModeControl.selectedSegmentIndex) ?? .trackPowerOff
        settings.directionChangeStops = directionSwitch.isOn
        settings.keepScreenOn = screenSwitch.isOn
        settings.autoConnect = autoConnectSwitch.isOn
        settings.turnoutSwitchTime = Int(turnoutStepper.value)
        client.turnoutSwitchTime = settings.turnoutSwitchTime
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenOn
        if let row = rowIndex(of: .turnoutTime) {
            tableView.reloadRows(at: [IndexPath(row: row, section: Section.settings.rawValue)], with: .none)
        }
    }

    private func connectTapped() {
        view.endEditing(true)
        if client.connectionState != .disconnected {
            client.disconnect()
            return
        }
        let host = (hostField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard let port = UInt16(portField.text ?? ""), !host.isEmpty else {
            showMessage("Ungültige Eingabe", "Bitte IP-Adresse und Port prüfen.")
            return
        }
        settings.host = host
        settings.port = port
        client.connect(host: host, port: port)
        if let err = client.lastError {
            showMessage("Verbindung nicht möglich", err)
        }
    }

    // MARK: Zeilen

    private enum Row {
        case host, port, connect, status
        case hardware, firmware, serial, xbus
        case mainCurrent, progCurrent, filteredCurrent, temperature, supply, track, flags
        case stopMode, directionStops, keepScreen, autoConnect, turnoutTime, simulatorHint
    }

    private func rows(_ section: Section) -> [Row] {
        switch section {
        case .connection: return [.host, .port, .connect, .status]
        case .station: return [.hardware, .firmware, .serial, .xbus]
        case .state: return [.mainCurrent, .progCurrent, .filteredCurrent, .temperature, .supply, .track, .flags]
        case .settings: return [.stopMode, .directionStops, .keepScreen, .autoConnect, .turnoutTime, .simulatorHint]
        }
    }

    private func rowIndex(of row: Row) -> Int? {
        return rows(.settings).firstIndex(of: row)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows(Section(rawValue: section)!).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .connection: return "Verbindung zur Z21"
        case .station: return "Zentrale"
        case .state: return "Systemzustand"
        case .settings: return "Einstellungen"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if Section(rawValue: section) == .connection {
            return "Werkseinstellung der Z21: 192.168.0.111, Port 21105. Das iPad muss im WLAN des Z21-Routers sein."
        }
        return nil
    }

    private func valueCell(_ title: String, _ value: String?) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        Theme.styleCell(cell)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = value ?? "–"
        cell.detailTextLabel?.font = Theme.monoFont(17)
        return cell
    }

    private func controlCell(_ title: String, _ control: UIView, width: CGFloat? = nil) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        Theme.styleCell(cell)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        if let width = width {
            control.frame = CGRect(x: 0, y: 0, width: width, height: 32)
        }
        cell.accessoryView = control
        return cell
    }

    private func milli(_ v: Int?, unit: String) -> String? {
        guard let v = v else { return nil }
        if unit == "V" { return String(format: "%.2f V", Double(v) / 1000) }
        return "\(v) mA"
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let state = client.systemState
        switch rows(Section(rawValue: indexPath.section)!)[indexPath.row] {
        case .host: return controlCell("IP-Adresse", hostField, width: 220)
        case .port: return controlCell("Port", portField, width: 120)
        case .connect:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            Theme.styleCell(cell)
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = Theme.font(17, bold: true)
            if client.connectionState == .disconnected {
                cell.textLabel?.text = "Verbinden"
                cell.textLabel?.textColor = Theme.green
            } else {
                cell.textLabel?.text = "Trennen"
                cell.textLabel?.textColor = Theme.red
            }
            return cell
        case .status:
            let text: String
            switch client.connectionState {
            case .connected: text = "Verbunden mit \(client.host)"
            case .connecting: text = "Verbinde mit \(client.host) …"
            case .disconnected: text = client.lastError ?? "Nicht verbunden"
            }
            let cell = valueCell("Status", text)
            cell.detailTextLabel?.textColor = client.connectionState == .connected ? Theme.green : Theme.functionOn
            return cell
        case .hardware: return valueCell("Hardware", client.hardwareType.map { Z21Codec.hardwareName($0) })
        case .firmware: return valueCell("Firmware", client.firmware)
        case .serial: return valueCell("Seriennummer", client.serialNumber.map { "\($0)" })
        case .xbus: return valueCell("X-Bus-Version", client.xbusVersion)
        case .mainCurrent: return valueCell("Strom Hauptgleis", milli(state?.mainCurrent, unit: "mA"))
        case .progCurrent: return valueCell("Strom Programmiergleis", milli(state?.progCurrent, unit: "mA"))
        case .filteredCurrent: return valueCell("Strom Hauptgleis (gefiltert)", milli(state?.filteredMainCurrent, unit: "mA"))
        case .temperature: return valueCell("Temperatur", state.map { "\($0.temperature) °C" })
        case .supply: return valueCell("Versorgungsspannung", milli(state?.supplyVoltage, unit: "V"))
        case .track: return valueCell("Gleisspannung", milli(state?.vccVoltage, unit: "V"))
        case .flags:
            var flags: [String] = []
            if let s = state {
                if s.centralState.contains(.emergencyStop) { flags.append("Nothalt") }
                if s.centralState.contains(.trackVoltageOff) { flags.append("Gleis aus") }
                if s.centralState.contains(.shortCircuit) { flags.append("Kurzschluss") }
                if s.centralState.contains(.programmingModeActive) { flags.append("Programmiermodus") }
                if s.centralStateEx.contains(.highTemperature) { flags.append("Übertemperatur") }
                if s.centralStateEx.contains(.powerLost) { flags.append("Unterspannung") }
                if s.centralStateEx.contains(.shortCircuitExternal) { flags.append("Kurzschluss extern") }
                if s.centralStateEx.contains(.shortCircuitInternal) { flags.append("Kurzschluss intern") }
            }
            return valueCell("Meldungen", state == nil ? nil : (flags.isEmpty ? "keine" : flags.joined(separator: ", ")))
        case .stopMode: return controlCell("STOP-Taste", stopModeControl, width: 330)
        case .directionStops: return controlCell("Richtungswechsel hält Lok an", directionSwitch)
        case .keepScreen: return controlCell("Bildschirm nicht sperren", screenSwitch)
        case .autoConnect: return controlCell("Beim Start automatisch verbinden", autoConnectSwitch)
        case .turnoutTime:
            let cell = controlCell("Schaltzeit Weichen: \(settings.turnoutSwitchTime) ms", turnoutStepper)
            return cell
        case .simulatorHint:
            let cell = valueCell("Testen ohne Z21", "tools/z21_simulator.py")
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if rows(Section(rawValue: indexPath.section)!)[indexPath.row] == .connect {
            connectTapped()
        }
    }

    // MARK: Z21ClientObserver

    private func reload(_ section: Section) {
        guard isViewLoaded, view.window != nil else { return }
        let rowsToReload = (0..<rows(section).count).map { IndexPath(row: $0, section: section.rawValue) }
        tableView.reloadRows(at: rowsToReload, with: .none)
    }

    func z21ClientConnectionChanged(_ client: Z21Client) {
        guard isViewLoaded, view.window != nil else { return }
        tableView.reloadRows(at: [IndexPath(row: 2, section: 0), IndexPath(row: 3, section: 0)], with: .none)
    }

    func z21ClientInfoChanged(_ client: Z21Client) {
        reload(.station)
    }

    func z21ClientSystemStateChanged(_ client: Z21Client) {
        reload(.state)
    }
}
