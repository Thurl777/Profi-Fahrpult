import UIKit

/// Messpunkte einer Lok: Kennlinie als Grafik, Liste der Punkte, Zugang zur Einmess-Hilfe
final class SpeedCurveViewController: UITableViewController {

    /// Wird bei jeder Änderung mit allen Messpunkten aufgerufen
    var onChange: (([SpeedPoint]) -> Void)?

    private var loco: Locomotive
    private let graph = SpeedCurveGraphView()

    private var points: [SpeedPoint] {
        get { return loco.speedPoints ?? [] }
        set {
            loco.speedPoints = newValue.isEmpty ? nil : newValue.sorted { $0.fraction < $1.fraction }
            onChange?(loco.speedPoints ?? [])
            refresh()
        }
    }

    private var maxStep: Int { return loco.speedSteps.maxStep }

    init(loco: Locomotive) {
        self.loco = loco
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Geschwindigkeit"
        tableView.backgroundColor = Theme.background
        // Die Breite des Kopfbereichs passt die Tabelle selbst an. Ihn in viewDidLayoutSubviews
        // neu zu setzen, löst jedes Mal einen weiteren Layout-Durchlauf aus und kann die App blockieren.
        graph.frame = CGRect(x: 0, y: 0, width: max(tableView.bounds.width, 320), height: 240)
        graph.autoresizingMask = [.flexibleWidth]
        tableView.tableHeaderView = graph
        refresh()
    }

    private func refresh() {
        graph.curve = loco.speedCurve
        graph.maxStep = maxStep
        graph.measuredPoints = points
        tableView.reloadData()
    }

    // MARK: Tabelle

    private enum Section: Int {
        case points = 0
        case actions
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == Section.points.rawValue { return points.count + 1 }
        return points.isEmpty ? 1 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == Section.points.rawValue ? "Messpunkte (\(loco.speedSteps.title))" : "Einmessen"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == Section.points.rawValue {
            return "Fahrstufe 0 ist immer 0 km/h. Über dem höchsten Messpunkt wird mit der Steigung der letzten Strecke weitergerechnet."
        }
        return "Mit drei Belegtmeldern auf einem Messgleis: Die Lok fährt darüber, die App misst die Zeit zwischen den Meldern und rechnet die Maßstabsgeschwindigkeit aus – einzeln je Fahrstufe oder automatisch für mehrere."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        Theme.styleCell(cell)
        if indexPath.section == Section.points.rawValue {
            if indexPath.row < points.count {
                let p = points[indexPath.row]
                cell.textLabel?.text = "Fahrstufe \(p.step(maxStep: maxStep))"
                cell.detailTextLabel?.text = SpeedFormat.kmh(p.kmh)
                cell.detailTextLabel?.font = Theme.monoFont(17)
            } else {
                cell.textLabel?.text = "Messpunkt von Hand eingeben …"
                cell.textLabel?.textColor = Theme.accent
            }
        } else if indexPath.row == 0 {
            cell.textLabel?.text = "Einmessen mit Belegtmeldern …"
            cell.textLabel?.textColor = Theme.accent
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.textLabel?.text = "Alle Messpunkte löschen"
            cell.textLabel?.textColor = Theme.red
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == Section.points.rawValue {
            editPoint(at: indexPath.row < points.count ? indexPath.row : nil)
        } else if indexPath.row == 0 {
            let measure = SpeedMeasureViewController(loco: loco)
            measure.onAddPoint = { [weak self] point in
                guard let self = self else { return }
                let step = point.step(maxStep: self.maxStep)
                self.points = self.points.filter { $0.step(maxStep: self.maxStep) != step } + [point]
            }
            navigationController?.pushViewController(measure, animated: true)
        } else {
            let alert = UIAlertController(title: "Alle Messpunkte löschen?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Löschen", style: .destructive) { [weak self] _ in
                self?.points = []
            })
            present(alert, animated: true, completion: nil)
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == Section.points.rawValue && indexPath.row < points.count
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.row < points.count else { return }
        var list = points
        list.remove(at: indexPath.row)
        points = list
    }

    // MARK: Messpunkt von Hand

    private func editPoint(at index: Int?) {
        let existing = index.map { points[$0] }
        let alert = UIAlertController(title: existing == nil ? "Neuer Messpunkt" : "Messpunkt ändern",
                                      message: "Fahrstufe 1 – \(maxStep) und gemessene Maßstabsgeschwindigkeit",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Fahrstufe"
            tf.keyboardType = .numberPad
            if let p = existing { tf.text = "\(p.step(maxStep: self.maxStep))" }
        }
        alert.addTextField { tf in
            tf.placeholder = "km/h"
            tf.keyboardType = .decimalPad
            if let p = existing { tf.text = SpeedFormat.number(p.kmh, digits: 1) }
        }
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Übernehmen", style: .default) { [weak self, weak alert] _ in
            guard let self = self else { return }
            let stepText = alert?.textFields?[0].text ?? ""
            let kmhText = alert?.textFields?[1].text ?? ""
            guard let step = Int(stepText), step >= 1, step <= self.maxStep,
                  let kmh = SpeedFormat.parse(kmhText), kmh >= 0, kmh < 1000 else {
                self.showMessage("Ungültige Eingabe", "Fahrstufe 1 bis \(self.maxStep) und km/h als Zahl eingeben.")
                return
            }
            var list = self.points
            if let i = index { list.remove(at: i) }
            list = list.filter { $0.step(maxStep: self.maxStep) != step }
            list.append(SpeedPoint(step: step, maxStep: self.maxStep, kmh: kmh))
            self.points = list
        })
        present(alert, animated: true, completion: nil)
    }
}

/// Zahlen deutsch formatieren und einlesen (Komma als Dezimaltrennzeichen)
enum SpeedFormat {
    static func number(_ value: Double, digits: Int) -> String {
        return String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func kmh(_ value: Double) -> String {
        return number(value, digits: 1) + " km/h"
    }

    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(t)
    }
}

/// Grafik der Kennlinie: Fahrstufe (waagerecht) gegen km/h (senkrecht)
final class SpeedCurveGraphView: UIView {

    var curve: SpeedCurve? { didSet { setNeedsDisplay() } }
    var maxStep: Int = 126 { didSet { setNeedsDisplay() } }
    var measuredPoints: [SpeedPoint] = [] { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        contentMode = .redraw
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ rect: CGRect) {
        guard let curve = curve, maxStep > 0 else { return }
        let box = bounds.insetBy(dx: 16, dy: 12)
        let plot = CGRect(x: box.minX + 44, y: box.minY + 8, width: box.width - 56, height: box.height - 38)
        guard plot.width > 40, plot.height > 40 else { return }

        let panel = UIBezierPath(roundedRect: box, cornerRadius: 6)
        Theme.panelBottom.setFill()
        panel.fill()
        Theme.panelBorder.setStroke()
        panel.lineWidth = 1
        panel.stroke()

        let yMax = Double(max(curve.scaleMax, 10))
        func pt(_ step: Double, _ kmh: Double) -> CGPoint {
            return CGPoint(x: plot.minX + plot.width * CGFloat(step / Double(maxStep)),
                           y: plot.maxY - plot.height * CGFloat(min(kmh, yMax) / yMax))
        }

        let labelAttrs: [NSAttributedString.Key: Any] = [.font: Theme.font(11, bold: true), .foregroundColor: Theme.textDim]

        // Raster km/h: höchstens 8 Linien, auch bei sehr hohen Werten (sonst endlos viele Linien)
        let yStep = [10.0, 20, 50, 100, 200, 500].first { yMax / $0 <= 8 } ?? (yMax / 8).rounded(.up)
        var y = 0.0
        while y <= yMax + 0.001 {
            let p = pt(0, y)
            let grid = UIBezierPath()
            grid.move(to: p)
            grid.addLine(to: CGPoint(x: plot.maxX, y: p.y))
            grid.lineWidth = 1
            Theme.rgb(0xB4B7BD).setStroke()
            grid.stroke()
            let text = "\(Int(y))" as NSString
            let size = text.size(withAttributes: labelAttrs)
            text.draw(at: CGPoint(x: plot.minX - size.width - 6, y: p.y - size.height / 2), withAttributes: labelAttrs)
            y += yStep
        }

        // Achse Fahrstufen
        let xMarks = maxStep >= 100 ? [0, 25, 50, 75, 100, 126].filter { $0 <= maxStep } : [0, maxStep / 4, maxStep / 2, maxStep * 3 / 4, maxStep]
        for s in xMarks {
            let p = pt(Double(s), 0)
            let text = "\(s)" as NSString
            let size = text.size(withAttributes: labelAttrs)
            text.draw(at: CGPoint(x: p.x - size.width / 2, y: plot.maxY + 4), withAttributes: labelAttrs)
        }
        let axisTitle = "Fahrstufe" as NSString
        axisTitle.draw(at: CGPoint(x: plot.maxX - axisTitle.size(withAttributes: labelAttrs).width, y: plot.maxY + 16),
                       withAttributes: labelAttrs)
        ("km/h" as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 2), withAttributes: labelAttrs)

        // Kennlinie
        let line = UIBezierPath()
        line.move(to: pt(0, 0))
        for s in 1...maxStep {
            line.addLine(to: pt(Double(s), curve.kmh(atStep: s)))
        }
        line.lineWidth = 3
        line.lineJoinStyle = .round
        if !curve.hasMeasurements {
            line.setLineDash([6, 4], count: 2, phase: 0)
        }
        Theme.accent.setStroke()
        line.stroke()

        // Messpunkte
        for p in measuredPoints {
            let c = pt(Double(p.step(maxStep: maxStep)), p.kmh)
            let dot = UIBezierPath(ovalIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
            Theme.functionOn.setFill()
            dot.fill()
            UIColor.black.setStroke()
            dot.lineWidth = 1.5
            dot.stroke()
        }
    }
}
