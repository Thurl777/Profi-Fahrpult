import UIKit

/// Bearbeiten einer Lok: Name, Adresse, Fahrstufen, Bild und Funktionsbelegung
final class LocoEditViewController: UITableViewController, UITextFieldDelegate,
                                    UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    private var loco: Locomotive
    private let isNew: Bool
    private var pendingImage: UIImage?
    private var removeImage = false

    private let nameField = UITextField()
    private let addressField = UITextField()
    private let vmaxField = UITextField()
    private let stepsControl = UISegmentedControl(items: ["14 FS", "28 FS", "128 FS"])
    private let previewImage = LocoImageView()

    private enum Section: Int {
        case general = 0
        case speed
        case image
        case functions
        case actions
    }

    init(loco: Locomotive, isNew: Bool) {
        self.loco = loco
        self.isNew = isNew
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew ? "Neue Lok" : loco.name
        tableView.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))

        for tf in [nameField, addressField, vmaxField] {
            tf.textColor = Theme.text
            tf.font = Theme.font(17)
            tf.textAlignment = .right
            tf.delegate = self
            tf.clearButtonMode = .whileEditing
            tf.keyboardAppearance = .dark
        }
        nameField.text = loco.name
        nameField.autocapitalizationType = .words
        addressField.text = "\(loco.address)"
        addressField.keyboardType = .numberPad
        vmaxField.text = "\(loco.maxSpeedKmh)"
        vmaxField.keyboardType = .numberPad
        switch loco.speedSteps {
        case .steps14: stepsControl.selectedSegmentIndex = 0
        case .steps28: stepsControl.selectedSegmentIndex = 1
        case .steps128: stepsControl.selectedSegmentIndex = 2
        }
        stepsControl.tintColor = Theme.accent
        stepsControl.addTarget(self, action: #selector(stepsChanged), for: .valueChanged)
        previewImage.image = LocoStore.shared.image(for: loco)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateVmaxField()
        tableView.reloadSections(IndexSet([Section.speed.rawValue, Section.functions.rawValue]), with: .none)
    }

    /// Fahrstufen laut Auswahl (auch wenn noch nicht gespeichert)
    private var currentSpeedSteps: SpeedSteps {
        return [SpeedSteps.steps14, .steps28, .steps128][max(0, stepsControl.selectedSegmentIndex)]
    }

    private var hasMeasurements: Bool {
        return !(loco.speedPoints ?? []).isEmpty
    }

    /// Mit Messpunkten ergibt sich die Höchstgeschwindigkeit aus der Kennlinie
    private func updateVmaxField() {
        if hasMeasurements {
            var l = loco
            l.speedSteps = currentSpeedSteps
            vmaxField.text = "\(Int(l.speedCurve.topSpeed.rounded()))"
            vmaxField.isEnabled = false
            vmaxField.textColor = Theme.textDim
        } else {
            vmaxField.isEnabled = true
            vmaxField.textColor = Theme.text
        }
    }

    private func showSpeedCurve() {
        view.endEditing(true)
        var draft = loco
        draft.speedSteps = currentSpeedSteps
        if !hasMeasurements, let vmax = Int(vmaxField.text ?? ""), vmax > 0 {
            draft.maxSpeedKmh = vmax
        }
        if let addr = Int(addressField.text ?? ""), addr >= 1, addr <= 9999 {
            draft.address = UInt16(addr)
        }
        let editor = SpeedCurveViewController(loco: draft)
        editor.onChange = { [weak self] points in
            self?.loco.speedPoints = points.isEmpty ? nil : points
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func stepsChanged() {
        updateVmaxField()
    }

    // MARK: Speichern

    @objc private func cancel() {
        view.endEditing(true)
        dismiss(animated: true, completion: nil)
    }

    @objc private func save() {
        view.endEditing(true)
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showMessage("Bitte einen Namen eingeben")
            return
        }
        guard let addr = Int(addressField.text ?? ""), addr >= 1, addr <= 9999 else {
            showMessage("Ungültige Adresse", "Erlaubt sind die Adressen 1 bis 9999.")
            return
        }
        if let other = LocoStore.shared.loco(address: UInt16(addr)), other.id != loco.id {
            showMessage("Adresse bereits vergeben", "Die Adresse \(addr) wird schon von „\(other.name)“ verwendet.")
            return
        }
        let vmax = Int(vmaxField.text ?? "") ?? 120
        loco.name = name
        loco.address = UInt16(addr)
        loco.speedSteps = currentSpeedSteps
        if hasMeasurements {
            loco.maxSpeedKmh = max(1, min(Int(loco.speedCurve.topSpeed.rounded()), 999))
        } else {
            loco.maxSpeedKmh = max(1, min(vmax, 999))
        }
        if removeImage {
            loco.imageFile = nil
        }
        if let img = pendingImage, let file = LocoStore.shared.storeImage(img, for: loco) {
            loco.imageFile = file
        }
        LocoStore.shared.update(loco)
        dismiss(animated: true, completion: nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: Tabelle

    override func numberOfSections(in tableView: UITableView) -> Int { return 5 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .general: return 3
        case .speed: return 2
        case .image: return 2
        case .functions: return Locomotive.functionCount
        case .actions: return isNew ? 0 : 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .general: return "Allgemein"
        case .speed: return "Geschwindigkeitsanzeige"
        case .image: return "Lokbild"
        case .functions: return "Funktionen"
        case .actions: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .speed else { return nil }
        return hasMeasurements
            ? "Der Tacho zeigt die eingemessene Maßstabsgeschwindigkeit. Zwischen den Messpunkten wird gerechnet."
            : "Ohne Messpunkte wird gleichmäßig von 0 bis zu diesem Wert gerechnet."
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == Section.image.rawValue && indexPath.row == 0 { return 120 }
        return 50
    }

    private func fieldCell(_ title: String, _ field: UIView, width: CGFloat = 260) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        Theme.styleCell(cell)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        field.frame = CGRect(x: 0, y: 0, width: width, height: 34)
        cell.accessoryView = field
        return cell
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .general:
            switch indexPath.row {
            case 0: return fieldCell("Name", nameField)
            case 1: return fieldCell("Adresse", addressField)
            default: return fieldCell("Fahrstufen", stepsControl)
            }
        case .speed:
            if indexPath.row == 0 {
                return fieldCell("km/h bei höchster Fahrstufe", vmaxField, width: 120)
            }
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            Theme.styleCell(cell)
            cell.textLabel?.text = "Messpunkte und Einmessen"
            let count = loco.speedPoints?.count ?? 0
            cell.detailTextLabel?.text = count == 0 ? "keine" : (count == 1 ? "1 Punkt" : "\(count) Punkte")
            cell.accessoryType = .disclosureIndicator
            return cell
        case .image:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            Theme.styleCell(cell)
            if indexPath.row == 0 {
                cell.selectionStyle = .none
                previewImage.frame = CGRect(x: 15, y: 10, width: 220, height: 100)
                previewImage.autoresizingMask = []
                cell.contentView.addSubview(previewImage)
            } else {
                cell.textLabel?.text = "Bild auswählen …"
                cell.textLabel?.textColor = Theme.accent
            }
            return cell
        case .functions:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            Theme.styleCell(cell)
            let f = loco.function(indexPath.row)
            cell.textLabel?.text = "F\(f.index)   \(f.name)"
            cell.detailTextLabel?.text = f.momentary ? "Moment" : "Dauer"
            cell.imageView?.image = FunctionIconRenderer.image(f.icon, size: 28, color: .white) ?? blankIcon()
            cell.accessoryType = .disclosureIndicator
            return cell
        case .actions:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            Theme.styleCell(cell)
            cell.textLabel?.text = "Lok löschen"
            cell.textLabel?.textColor = Theme.red
            cell.textLabel?.textAlignment = .center
            return cell
        }
    }

    private func blankIcon() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 28, height: 28), false, 0)
        defer { UIGraphicsEndImageContext() }
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font(13, bold: true), .foregroundColor: Theme.textDim]
        ("F" as NSString).draw(at: CGPoint(x: 9, y: 6), withAttributes: attrs)
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .general:
            break
        case .speed:
            if indexPath.row == 1 {
                showSpeedCurve()
            }
        case .image:
            if indexPath.row == 1, let cell = tableView.cellForRow(at: indexPath) {
                chooseImage(from: cell)
            }
        case .functions:
            let editor = FunctionEditViewController(function: loco.function(indexPath.row))
            editor.onChange = { [weak self] f in
                self?.loco.setFunction(f)
            }
            navigationController?.pushViewController(editor, animated: true)
        case .actions:
            let alert = UIAlertController(title: "„\(loco.name)“ löschen?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Löschen", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                LocoStore.shared.delete(id: self.loco.id)
                self.dismiss(animated: true, completion: nil)
            })
            present(alert, animated: true, completion: nil)
        }
    }

    // MARK: Bild

    private func chooseImage(from cell: UIView) {
        let sheet = UIAlertController(title: "Lokbild", message: nil, preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            sheet.addAction(UIAlertAction(title: "Aus Fotomediathek", style: .default) { [weak self] _ in
                self?.presentPicker(.photoLibrary, from: cell)
            })
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Foto aufnehmen", style: .default) { [weak self] _ in
                self?.presentPicker(.camera, from: cell)
            })
        }
        sheet.addAction(UIAlertAction(title: "Bild entfernen", style: .destructive) { [weak self] _ in
            self?.pendingImage = nil
            self?.removeImage = true
            self?.previewImage.image = nil
        })
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = cell
        sheet.popoverPresentationController?.sourceRect = cell.bounds
        present(sheet, animated: true, completion: nil)
    }

    private func presentPicker(_ source: UIImagePickerController.SourceType, from view: UIView) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        if source == .photoLibrary {
            picker.modalPresentationStyle = .popover
            picker.popoverPresentationController?.sourceView = view
            picker.popoverPresentationController?.sourceRect = view.bounds
        }
        present(picker, animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let img = info[.originalImage] as? UIImage {
            pendingImage = img
            removeImage = false
            previewImage.image = img
        }
        picker.dismiss(animated: true, completion: nil)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}

/// Bearbeiten einer einzelnen Funktion (Name, Symbol, Moment/Dauer)
final class FunctionEditViewController: UITableViewController, UITextFieldDelegate {

    var onChange: ((LocoFunction) -> Void)?
    private var function: LocoFunction
    private let nameField = UITextField()
    private let momentarySwitch = UISwitch()
    private let icons = FunctionIcon.allCases

    init(function: LocoFunction) {
        self.function = function
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Funktion F\(function.index)"
        tableView.backgroundColor = Theme.background
        nameField.text = function.name
        nameField.textColor = Theme.text
        nameField.textAlignment = .right
        nameField.delegate = self
        nameField.keyboardAppearance = .dark
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        momentarySwitch.isOn = function.momentary
        momentarySwitch.addTarget(self, action: #selector(momentaryChanged), for: .valueChanged)
    }

    @objc private func nameChanged() {
        function.name = nameField.text ?? ""
        onChange?(function)
    }

    @objc private func momentaryChanged() {
        function.momentary = momentarySwitch.isOn
        onChange?(function)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 2 : icons.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Funktion" : "Symbol"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        Theme.styleCell(cell)
        if indexPath.section == 0 {
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                cell.textLabel?.text = "Bezeichnung"
                nameField.frame = CGRect(x: 0, y: 0, width: 240, height: 34)
                cell.accessoryView = nameField
            } else {
                cell.textLabel?.text = "Moment-Funktion (nur solange gedrückt)"
                cell.accessoryView = momentarySwitch
            }
        } else {
            let icon = icons[indexPath.row]
            cell.textLabel?.text = icon.title
            cell.imageView?.image = FunctionIconRenderer.image(icon, size: 30, color: Theme.functionOn)
            cell.accessoryType = icon == function.icon ? .checkmark : .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let icon = icons[indexPath.row]
        function.icon = icon
        let generic = function.name.isEmpty || function.name == "Funktion \(function.index)"
            || icons.contains { $0.title == function.name }
        if generic && icon != .generic {
            function.name = icon.title
            nameField.text = icon.title
        }
        onChange?(function)
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }
}
