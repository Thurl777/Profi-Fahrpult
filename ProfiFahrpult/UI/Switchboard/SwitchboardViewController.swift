import UIKit

/// Stellpult für Magnetartikel: 16 Weichen/Signale pro Seite, je eine rote und grüne Taste
/// (entspricht dem "Keyboard" der ECoS bzw. der Weichensteuerung der Z21-App).
final class SwitchboardViewController: UIViewController, Z21ClientObserver {

    static let perPage = 16

    private let client = Z21Client.shared
    private let header = PanelView(title: nil)
    private let pageLabel = UILabel()
    private let prevButton = ECoSButton(title: "◀", style: .normal)
    private let nextButton = ECoSButton(title: "▶", style: .normal)
    private let gotoButton = ECoSButton(title: "Gehe zu …", style: .accent)
    private var tiles: [AccessoryTile] = []

    private var page: Int = AppSettings.shared.accessoryPage {
        didSet {
            AppSettings.shared.accessoryPage = page
            reloadTiles(request: true)
        }
    }

    private var maxPage: Int { return Int(AccessoryStore.maxAddress) / SwitchboardViewController.perPage - 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        view.addSubview(header)
        pageLabel.font = Theme.font(20, bold: true)
        pageLabel.textColor = Theme.text
        pageLabel.textAlignment = .center
        pageLabel.adjustsFontSizeToFitWidth = true
        pageLabel.minimumScaleFactor = 0.6
        header.contentView.addSubview(pageLabel)
        for b in [prevButton, nextButton] {
            b.titleLabel?.font = Theme.font(22, bold: true)
            header.contentView.addSubview(b)
        }
        header.contentView.addSubview(gotoButton)
        prevButton.addTarget(self, action: #selector(prevPage), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
        gotoButton.addTarget(self, action: #selector(gotoAddress), for: .touchUpInside)

        for _ in 0..<SwitchboardViewController.perPage {
            let tile = AccessoryTile()
            tile.onSwitch = { [weak self] address, output in
                self?.client.setTurnout(address: address, output: output)
            }
            tile.onEdit = { [weak self] tile in
                self?.edit(tile)
            }
            view.addSubview(tile)
            tiles.append(tile)
        }
        page = min(max(0, page), maxPage)
        client.addObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(configChanged),
                                               name: .accessoryStoreChanged, object: nil)
    }

    deinit {
        client.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadTiles(request: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let pad: CGFloat = 8
        let w = view.bounds.width
        header.frame = CGRect(x: pad, y: pad, width: w - 2 * pad, height: 60)
        let hw = header.contentView.bounds.width
        prevButton.frame = CGRect(x: 8, y: 8, width: 70, height: 44)
        nextButton.frame = CGRect(x: 86, y: 8, width: 70, height: 44)
        gotoButton.frame = CGRect(x: hw - 148, y: 8, width: 140, height: 44)
        pageLabel.frame = CGRect(x: 160, y: 8, width: hw - 320, height: 44)

        let cols: CGFloat = 4
        let rows = CGFloat(SwitchboardViewController.perPage) / cols
        let top = header.frame.maxY + pad
        let tileW = floor((w - pad * (cols + 1)) / cols)
        let tileH = floor((view.bounds.height - top - pad * rows) / rows)
        for (i, tile) in tiles.enumerated() {
            let col = CGFloat(i % Int(cols))
            let row = CGFloat(i / Int(cols))
            tile.frame = CGRect(x: pad + col * (tileW + pad), y: top + row * (tileH + pad), width: tileW, height: tileH)
        }
    }

    private func reloadTiles(request: Bool) {
        let first = page * SwitchboardViewController.perPage + 1
        let last = first + SwitchboardViewController.perPage - 1
        pageLabel.text = "Adressen \(first) – \(last)"
        prevButton.isEnabled = page > 0
        nextButton.isEnabled = page < maxPage
        for (i, tile) in tiles.enumerated() {
            let address = UInt16(first + i)
            tile.configure(address: address, config: AccessoryStore.shared.config(address),
                           position: client.turnouts[address] ?? .unknown)
            if request {
                client.requestTurnoutInfo(address)
            }
        }
    }

    @objc private func configChanged() {
        reloadTiles(request: false)
    }

    @objc private func prevPage() { page = max(0, page - 1) }
    @objc private func nextPage() { page = min(maxPage, page + 1) }

    @objc private func gotoAddress() {
        let alert = UIAlertController(title: "Gehe zu Adresse", message: "1 – \(AccessoryStore.maxAddress)", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self, let v = Int(alert.textFields?.first?.text ?? ""),
                  v >= 1, v <= Int(AccessoryStore.maxAddress) else { return }
            self.page = (v - 1) / SwitchboardViewController.perPage
        })
        present(alert, animated: true, completion: nil)
    }

    private func edit(_ tile: AccessoryTile) {
        let editor = AccessoryEditViewController(address: tile.address)
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .popover
        nav.preferredContentSize = CGSize(width: 380, height: 520)
        nav.popoverPresentationController?.sourceView = tile
        nav.popoverPresentationController?.sourceRect = tile.bounds
        present(nav, animated: true, completion: nil)
    }

    // MARK: Z21ClientObserver

    func z21Client(_ client: Z21Client, turnoutChanged address: UInt16, position: TurnoutPosition) {
        for tile in tiles where tile.address == address {
            tile.position = position
        }
    }

    func z21ClientConnectionChanged(_ client: Z21Client) {
        if client.connectionState == .connected && view.window != nil {
            reloadTiles(request: true)
        }
    }
}

/// Eine Kachel im Stellpult
final class AccessoryTile: GradientView {

    var onSwitch: ((UInt16, Int) -> Void)?
    var onEdit: ((AccessoryTile) -> Void)?

    private(set) var address: UInt16 = 1
    private var config = AccessoryConfig.standard(address: 1)
    var position: TurnoutPosition = .unknown {
        didSet { updateState() }
    }

    private let addressLabel = UILabel()
    private let nameLabel = UILabel()
    private let symbol = AccessorySymbolView()
    private let redButton = ECoSButton(title: nil, style: .red)
    private let greenButton = ECoSButton(title: nil, style: .green)

    init() {
        super.init(colors: [Theme.panelTop, Theme.panelBottom], cornerRadius: 6, border: Theme.panelBorder)
        addressLabel.font = Theme.monoFont(18, bold: true)
        addressLabel.textColor = Theme.text
        nameLabel.font = Theme.font(12)
        nameLabel.textColor = Theme.textDim
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        ([addressLabel, nameLabel, symbol, redButton, greenButton] as [UIView]).forEach { addSubview($0) }
        redButton.addTarget(self, action: #selector(redTapped), for: .touchUpInside)
        greenButton.addTarget(self, action: #selector(greenTapped), for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        addGestureRecognizer(lp)
        let tap = UITapGestureRecognizer(target: self, action: #selector(symbolTapped))
        symbol.addGestureRecognizer(tap)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func configure(address: UInt16, config: AccessoryConfig, position: TurnoutPosition) {
        self.address = address
        self.config = config
        addressLabel.text = "\(address)"
        nameLabel.text = config.name.isEmpty ? config.kind.title : config.name
        symbol.kind = config.kind
        self.position = position
    }

    /// Ausgang (0/1), der der roten bzw. grünen Taste zugeordnet ist
    private var redOutput: Int { return config.inverted ? 1 : 0 }
    private var greenOutput: Int { return config.inverted ? 0 : 1 }

    private func updateState() {
        let isGreen: Bool?
        switch position {
        case .output1: isGreen = greenOutput == 0
        case .output2: isGreen = greenOutput == 1
        default: isGreen = nil
        }
        symbol.isGreen = isGreen
        redButton.markColor = isGreen == false ? Theme.text : nil
        greenButton.markColor = isGreen == true ? Theme.text : nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        addressLabel.frame = CGRect(x: 8, y: 4, width: 70, height: 24)
        nameLabel.frame = CGRect(x: 8, y: 26, width: w - 16, height: 16)
        let btnH = min(54, max(36, h * 0.32))
        let btnW = floor((w - 24) / 2)
        redButton.frame = CGRect(x: 8, y: h - 8 - btnH, width: btnW, height: btnH)
        greenButton.frame = CGRect(x: 16 + btnW, y: h - 8 - btnH, width: btnW, height: btnH)
        let symTop: CGFloat = 44
        symbol.frame = CGRect(x: 8, y: symTop, width: w - 16, height: max(10, redButton.frame.minY - symTop - 4))
        updateState()
    }

    @objc private func redTapped() { onSwitch?(address, redOutput) }
    @objc private func greenTapped() { onSwitch?(address, greenOutput) }

    /// Tippen auf das Symbol schaltet um
    @objc private func symbolTapped() {
        if symbol.isGreen == true {
            redTapped()
        } else {
            greenTapped()
        }
    }

    @objc private func longPressed(_ gr: UILongPressGestureRecognizer) {
        if gr.state == .began { onEdit?(self) }
    }
}

/// Symbol einer Weiche bzw. eines Signals mit Stellungsanzeige
final class AccessorySymbolView: UIView {

    var kind: AccessoryKind = .turnoutLeft { didSet { setNeedsDisplay() } }
    /// true = grün/gerade, false = rot/abzweigend, nil = unbekannt
    var isGreen: Bool? { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ rect: CGRect) {
        let w = bounds.width
        let h = bounds.height
        let cy = h / 2
        let lineW = max(4, min(w, h) * 0.09)
        let active = Theme.text
        let inactive = Theme.rgb(0xA9ACB2)

        func stroke(_ pts: [CGPoint], _ color: UIColor) {
            let p = UIBezierPath()
            p.lineWidth = lineW
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.move(to: pts[0])
            for q in pts.dropFirst() { p.addLine(to: q) }
            color.setStroke()
            p.stroke()
        }

        func lamp(_ center: CGPoint, _ r: CGFloat, _ color: UIColor, lit: Bool) {
            let path = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            (lit ? color : color.withBrightnessFactor(0.25)).setFill()
            path.fill()
            Theme.panelBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        switch kind {
        case .turnoutLeft, .turnoutRight:
            let dir: CGFloat = kind == .turnoutLeft ? -1 : 1
            let x0 = w * 0.12
            let x1 = w * 0.88
            let split = w * 0.38
            let branchEnd = CGPoint(x: x1 - w * 0.08, y: cy + dir * h * 0.32)
            let straight = isGreen != false
            let known = isGreen != nil
            // Zuerst den inaktiven Strang, dann den aktiven darüber
            if straight {
                stroke([CGPoint(x: split, y: cy), branchEnd], inactive)
                stroke([CGPoint(x: x0, y: cy), CGPoint(x: x1, y: cy)], known ? active : Theme.textDim)
            } else {
                stroke([CGPoint(x: split, y: cy), CGPoint(x: x1, y: cy)], inactive)
                stroke([CGPoint(x: x0, y: cy), CGPoint(x: split, y: cy), branchEnd], active)
            }
        case .signal:
            let r = min(w, h) * 0.16
            let mastX = w * 0.5
            let body = UIBezierPath(roundedRect: CGRect(x: mastX - r * 1.5, y: cy - r * 2.6, width: r * 3, height: r * 5.2),
                                    cornerRadius: r * 1.4)
            Theme.rgb(0x15171A).setFill()
            body.fill()
            lamp(CGPoint(x: mastX, y: cy - r * 1.25), r, Theme.red, lit: isGreen == false)
            lamp(CGPoint(x: mastX, y: cy + r * 1.25), r, Theme.green, lit: isGreen == true)
        case .decoupler:
            let color = isGreen == true ? active : Theme.textDim
            stroke([CGPoint(x: w * 0.1, y: cy), CGPoint(x: w * 0.9, y: cy)], inactive)
            let r = CGRect(x: w * 0.38, y: cy - h * 0.25, width: w * 0.24, height: h * 0.5)
            let p = UIBezierPath(roundedRect: r, cornerRadius: 4)
            color.setFill()
            p.fill()
        case .light:
            let r = min(w, h) * 0.3
            lamp(CGPoint(x: w / 2, y: cy), r, Theme.functionOn, lit: isGreen == true)
        case .generic:
            let r = min(w, h) * 0.18
            lamp(CGPoint(x: w * 0.35, y: cy), r, Theme.red, lit: isGreen == false)
            lamp(CGPoint(x: w * 0.65, y: cy), r, Theme.green, lit: isGreen == true)
        }
    }
}

/// Einstellungen eines Magnetartikels
final class AccessoryEditViewController: UITableViewController, UITextFieldDelegate {

    private let address: UInt16
    private var config: AccessoryConfig
    private let nameField = UITextField()
    private let invertSwitch = UISwitch()

    init(address: UInt16) {
        self.address = address
        self.config = AccessoryStore.shared.config(address)
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Adresse \(address)"
        tableView.backgroundColor = Theme.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        nameField.text = config.name
        nameField.placeholder = "z.B. W12 Bahnhof"
        nameField.textColor = Theme.text
        nameField.textAlignment = .right
        nameField.delegate = self
        nameField.keyboardAppearance = .light
        invertSwitch.isOn = config.inverted
    }

    @objc private func done() {
        config.name = (nameField.text ?? "").trimmingCharacters(in: .whitespaces)
        config.inverted = invertSwitch.isOn
        AccessoryStore.shared.setConfig(config, for: address)
        dismiss(animated: true, completion: nil)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 2 : AccessoryKind.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Allgemein" : "Typ"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        Theme.styleCell(cell)
        if indexPath.section == 0 {
            cell.selectionStyle = .none
            if indexPath.row == 0 {
                cell.textLabel?.text = "Name"
                nameField.frame = CGRect(x: 0, y: 0, width: 200, height: 34)
                cell.accessoryView = nameField
            } else {
                cell.textLabel?.text = "Rot/Grün vertauschen"
                cell.accessoryView = invertSwitch
            }
        } else {
            let kind = AccessoryKind.allCases[indexPath.row]
            cell.textLabel?.text = kind.title
            cell.accessoryType = kind == config.kind ? .checkmark : .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        config.kind = AccessoryKind.allCases[indexPath.row]
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }
}
