import UIKit

/// Lokliste: Übersicht aller Loks, Zuweisung an die Regler, Bearbeiten und Löschen
final class LocoListViewController: UITableViewController {

    private var locos: [Locomotive] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lokliste"
        tableView.backgroundColor = Theme.background
        tableView.rowHeight = 76
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addLoco))
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .locoStoreChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .throttleAssignmentChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reload() {
        locos = LocoStore.shared.sortedLocos
        tableView.reloadData()
    }

    @objc private func addLoco() {
        let next = (locos.map { Int($0.address) }.max() ?? 2) + 1
        let loco = Locomotive(name: "Neue Lok", address: UInt16(min(next, 9999)))
        edit(loco, isNew: true)
    }

    private func edit(_ loco: Locomotive, isNew: Bool) {
        let editor = LocoEditViewController(loco: loco, isNew: isNew)
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true, completion: nil)
    }

    // MARK: Tabelle

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return locos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LocoCell.reuseID) as? LocoCell ?? LocoCell(style: .default, reuseIdentifier: LocoCell.reuseID)
        let loco = locos[indexPath.row]
        var throttles: [String] = []
        for i in 0..<AppSettings.throttleCount where AppSettings.shared.throttleLocoID(i) == loco.id {
            throttles.append("Regler \(i + 1)")
        }
        cell.configure(loco, assignedTo: throttles.joined(separator: ", "))
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let loco = locos[indexPath.row]
        let sheet = UIAlertController(title: loco.name, message: "Adresse \(loco.address)", preferredStyle: .actionSheet)
        for i in 0..<AppSettings.throttleCount {
            sheet.addAction(UIAlertAction(title: "In Regler \(i + 1) übernehmen", style: .default) { _ in
                AppSettings.shared.setThrottleLocoID(loco.id, for: i)
            })
        }
        sheet.addAction(UIAlertAction(title: "Bearbeiten", style: .default) { [weak self] _ in
            self?.edit(loco, isNew: false)
        })
        sheet.addAction(UIAlertAction(title: "Duplizieren", style: .default) { _ in
            var copy = loco
            copy.id = UUID().uuidString
            copy.name = loco.name + " (Kopie)"
            copy.imageFile = nil
            LocoStore.shared.add(copy)
        })
        sheet.addAction(UIAlertAction(title: "Löschen", style: .destructive) { [weak self] _ in
            self?.confirmDelete(loco)
        })
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        if let pop = sheet.popoverPresentationController, let cell = tableView.cellForRow(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        present(sheet, animated: true, completion: nil)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func confirmDelete(_ loco: Locomotive) {
        let alert = UIAlertController(title: "„\(loco.name)“ löschen?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Löschen", style: .destructive) { _ in
            LocoStore.shared.delete(id: loco.id)
        })
        present(alert, animated: true, completion: nil)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            confirmDelete(locos[indexPath.row])
        }
    }
}

final class LocoCell: UITableViewCell {
    static let reuseID = "LocoCell"

    private let locoImage = LocoImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let throttleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        Theme.styleCell(self)
        nameLabel.font = Theme.font(19, bold: true)
        nameLabel.textColor = Theme.text
        detailLabel.font = Theme.font(14)
        detailLabel.textColor = Theme.textDim
        throttleLabel.font = Theme.font(13, bold: true)
        throttleLabel.textColor = Theme.accent
        throttleLabel.textAlignment = .right
        ([locoImage, nameLabel, detailLabel, throttleLabel] as [UIView]).forEach { contentView.addSubview($0) }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func configure(_ loco: Locomotive, assignedTo: String) {
        locoImage.image = LocoStore.shared.image(for: loco)
        nameLabel.text = loco.name
        detailLabel.text = "Adresse \(loco.address) · \(loco.speedSteps.title) · Vmax \(loco.maxSpeedKmh) km/h"
        throttleLabel.text = assignedTo
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = contentView.bounds.height
        let w = contentView.bounds.width
        locoImage.frame = CGRect(x: 12, y: 8, width: 110, height: h - 16)
        let x = locoImage.frame.maxX + 14
        throttleLabel.frame = CGRect(x: w - 170, y: 0, width: 158, height: h)
        nameLabel.frame = CGRect(x: x, y: 12, width: throttleLabel.frame.minX - x - 8, height: 26)
        detailLabel.frame = CGRect(x: x, y: 40, width: throttleLabel.frame.minX - x - 8, height: 20)
    }
}
