import UIKit

/// Einrichtung der Kontakt-Messstrecke: drei Melderadressen (links/Mitte/rechts) und die beiden
/// Streckenlängen dazwischen. Wird einmalig eingerichtet und danach von der Einmess-Hilfe jeder Lok verwendet.
final class ContactTrackConfigViewController: UITableViewController, UITextFieldDelegate {

    private let settings = AppSettings.shared

    private let leftField = UITextField()
    private let middleField = UITextField()
    private let rightField = UITextField()
    private let distanceLMField = UITextField()
    private let distanceMRField = UITextField()

    private enum Section: Int, CaseIterable {
        case addresses
        case distances
    }

    init() {
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Messgleis"
        tableView.backgroundColor = Theme.background

        for tf in [leftField, middleField, rightField] {
            tf.keyboardType = .numberPad
            tf.placeholder = "Adresse"
        }
        leftField.text = settings.contactAddressLeft > 0 ? "\(settings.contactAddressLeft)" : ""
        middleField.text = settings.contactAddressMiddle > 0 ? "\(settings.contactAddressMiddle)" : ""
        rightField.text = settings.contactAddressRight > 0 ? "\(settings.contactAddressRight)" : ""

        for tf in [distanceLMField, distanceMRField] {
            tf.keyboardType = .decimalPad
        }
        distanceLMField.text = SpeedFormat.number(settings.contactDistanceLeftMiddleCm, digits: 1)
        distanceMRField.text = SpeedFormat.number(settings.contactDistanceMiddleRightCm, digits: 1)

        for tf in [leftField, middleField, rightField, distanceLMField, distanceMRField] {
            tf.textColor = Theme.text
            tf.font = Theme.monoFont(17)
            tf.textAlignment = .right
            tf.delegate = self
            tf.clearButtonMode = .whileEditing
            tf.keyboardAppearance = .light
            tf.addTarget(self, action: #selector(valuesChanged), for: .editingChanged)
        }

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    @objc private func valuesChanged() {
        settings.contactAddressLeft = Int(leftField.text ?? "") ?? 0
        settings.contactAddressMiddle = Int(middleField.text ?? "") ?? 0
        settings.contactAddressRight = Int(rightField.text ?? "") ?? 0
        if let d = SpeedFormat.parse(distanceLMField.text ?? ""), d > 0 {
            settings.contactDistanceLeftMiddleCm = d
        }
        if let d = SpeedFormat.parse(distanceMRField.text ?? ""), d > 0 {
            settings.contactDistanceMiddleRightCm = d
        }
    }

    // MARK: Tabelle

    override func numberOfSections(in tableView: UITableView) -> Int { return Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Section(rawValue: section) == .addresses ? 3 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section) == .addresses ? "Melderadressen (R-Bus, 1 – 160)" : "Streckenlänge in cm"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if Section(rawValue: section) == .addresses {
            return "Drei Belegtmelder hintereinander auf einem geraden Gleisstück, in Fahrtrichtung: "
                + "links, Mitte, rechts. Die Lok löst beim Überfahren nacheinander alle drei Melder aus."
        }
        return "Abstand der Meldeabschnitte: links–Mitte und Mitte–rechts (jeweils vom Auslösepunkt zum nächsten)."
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { return 50 }

    private func fieldCell(_ title: String, _ field: UIView) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        Theme.styleCell(cell)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        field.frame = CGRect(x: 0, y: 0, width: 140, height: 34)
        cell.accessoryView = field
        return cell
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if Section(rawValue: indexPath.section) == .addresses {
            switch indexPath.row {
            case 0: return fieldCell("Links", leftField)
            case 1: return fieldCell("Mitte", middleField)
            default: return fieldCell("Rechts", rightField)
            }
        }
        return indexPath.row == 0 ? fieldCell("Links → Mitte", distanceLMField) : fieldCell("Mitte → Rechts", distanceMRField)
    }
}
