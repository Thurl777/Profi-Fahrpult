import UIKit

/// Fahrpult mit zwei Reglern nebeneinander (wie links/rechts an der ECoS)
final class DriveViewController: UIViewController {

    private var throttles: [ThrottleView] = []
    private let follower = HandheldFollower(throttleCount: AppSettings.throttleCount)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bar
        for i in 0..<AppSettings.throttleCount {
            let t = ThrottleView(index: i)
            t.onSelectLoco = { [weak self] throttle, source in
                self?.showPicker(for: throttle, from: source)
            }
            t.onSwap = {
                AppSettings.shared.swapThrottleLocos()
            }
            t.onEditLoco = { [weak self] _, loco in
                self?.editLoco(loco)
            }
            t.onUserActivity = { [weak self] throttle in
                self?.follower.noteAppUse(throttle: throttle.index)
            }
            view.addSubview(t)
            throttles.append(t)
        }
        reloadAssignments()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadAssignments),
                                               name: .throttleAssignmentChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadAssignments),
                                               name: .locoStoreChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let pad: CGFloat = 8
        let count = CGFloat(throttles.count)
        let w = floor((view.bounds.width - pad * (count + 1)) / count)
        for (i, t) in throttles.enumerated() {
            t.frame = CGRect(x: pad + CGFloat(i) * (w + pad), y: pad, width: w, height: view.bounds.height - 2 * pad)
        }
    }

    @objc private func reloadAssignments() {
        for t in throttles {
            let loco = LocoStore.shared.loco(id: AppSettings.shared.throttleLocoID(t.index))
            if loco != t.loco {
                t.setLoco(loco)
            }
        }
    }

    /// Öffnet die Lokeinstellungen (Messpunkte, Funktionen, …) direkt aus dem Fahrbildschirm
    private func editLoco(_ loco: Locomotive) {
        let editor = LocoEditViewController(loco: loco, isNew: false)
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true, completion: nil)
    }

    private func showPicker(for throttle: ThrottleView, from source: UIView) {
        let picker = LocoPickerViewController()
        picker.onPick = { [weak self] loco in
            AppSettings.shared.setThrottleLocoID(loco.id, for: throttle.index)
            self?.dismiss(animated: true, completion: nil)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .popover
        nav.preferredContentSize = CGSize(width: 360, height: 520)
        if let pop = nav.popoverPresentationController {
            pop.sourceView = source
            pop.sourceRect = source.bounds
            pop.permittedArrowDirections = [.up, .down]
            pop.backgroundColor = Theme.titleBottom
        }
        present(nav, animated: true, completion: nil)
    }
}

/// Auswahl einer Lok aus der Bibliothek oder per Adresseingabe
final class LocoPickerViewController: UITableViewController {

    var onPick: ((Locomotive) -> Void)?
    private var locos: [Locomotive] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lok wählen"
        tableView.backgroundColor = Theme.background
        tableView.rowHeight = 56
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        locos = LocoStore.shared.sortedLocos
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : locos.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? nil : "Lokliste"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        Theme.styleCell(cell)
        if indexPath.section == 0 {
            cell.textLabel?.text = "Adresse direkt eingeben …"
            cell.textLabel?.textColor = Theme.accent
            cell.imageView?.image = nil
        } else {
            let loco = locos[indexPath.row]
            cell.textLabel?.text = loco.name
            cell.textLabel?.font = Theme.font(17, bold: true)
            cell.detailTextLabel?.text = "Adresse \(loco.address) · \(loco.speedSteps.title)"
            cell.imageView?.image = thumbnail(for: loco)
        }
        return cell
    }

    private func thumbnail(for loco: Locomotive) -> UIImage? {
        let size = CGSize(width: 72, height: 40)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        if let img = LocoStore.shared.image(for: loco) {
            let scale = min(size.width / img.size.width, size.height / img.size.height)
            let w = img.size.width * scale
            let h = img.size.height * scale
            img.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        } else {
            let v = LocoImageView(frame: CGRect(origin: .zero, size: size))
            v.layer.render(in: UIGraphicsGetCurrentContext()!)
            v.draw(v.bounds)
        }
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            onPick?(locos[indexPath.row])
            return
        }
        let alert = UIAlertController(title: "Lokadresse", message: "Adresse 1 – 9999", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.placeholder = "z.B. 3"
        }
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Übernehmen", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text, let value = Int(text), value >= 1, value <= 9999 else {
                self?.showMessage("Ungültige Adresse")
                return
            }
            let loco = LocoStore.shared.locoCreatingIfNeeded(address: UInt16(value))
            self?.onPick?(loco)
        })
        present(alert, animated: true, completion: nil)
    }
}
