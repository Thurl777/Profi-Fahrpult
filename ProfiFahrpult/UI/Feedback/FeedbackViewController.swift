import UIKit

/// Anzeige der R-Bus-Rückmelder (Module 1–20 mit je 8 Eingängen)
final class FeedbackViewController: UIViewController, Z21ClientObserver {

    private let client = Z21Client.shared
    private let panels = [PanelView(title: "R-Bus Gruppe 1 · Module 1–10"),
                          PanelView(title: "R-Bus Gruppe 2 · Module 11–20")]
    private var rows: [FeedbackRow] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        for (g, panel) in panels.enumerated() {
            view.addSubview(panel)
            for m in 0..<10 {
                let row = FeedbackRow(module: g * 10 + m + 1)
                panel.contentView.addSubview(row)
                rows.append(row)
            }
        }
        client.addObserver(self)
    }

    deinit {
        client.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        client.requestFeedback()
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let pad: CGFloat = 8
        let landscape = view.bounds.width > view.bounds.height
        if landscape {
            let w = floor((view.bounds.width - 3 * pad) / 2)
            for (i, p) in panels.enumerated() {
                p.frame = CGRect(x: pad + CGFloat(i) * (w + pad), y: pad, width: w, height: view.bounds.height - 2 * pad)
            }
        } else {
            let h = floor((view.bounds.height - 3 * pad) / 2)
            for (i, p) in panels.enumerated() {
                p.frame = CGRect(x: pad, y: pad + CGFloat(i) * (h + pad), width: view.bounds.width - 2 * pad, height: h)
            }
        }
        for p in panels { p.layoutIfNeeded() }
        for (i, row) in rows.enumerated() {
            let container = panels[i / 10].contentView.bounds
            let rh = floor((container.height - 8) / 10)
            row.frame = CGRect(x: 8, y: 4 + CGFloat(i % 10) * rh, width: container.width - 16, height: rh)
        }
    }

    private func refresh() {
        for row in rows {
            row.update(byte: client.feedback[row.module - 1])
        }
    }

    func z21Client(_ client: Z21Client, feedbackChangedInGroup group: UInt8) {
        refresh()
    }

    func z21ClientConnectionChanged(_ client: Z21Client) {
        if client.connectionState == .connected {
            client.requestFeedback()
        }
    }
}

final class FeedbackRow: UIView {

    let module: Int
    private let label = UILabel()
    private var leds: [StatusLED] = []
    private var numbers: [UILabel] = []

    init(module: Int) {
        self.module = module
        super.init(frame: .zero)
        label.text = "Modul \(module)"
        label.font = Theme.font(15, bold: true)
        label.textColor = Theme.text
        addSubview(label)
        for i in 0..<8 {
            let led = StatusLED(frame: .zero)
            addSubview(led)
            leds.append(led)
            let n = UILabel()
            n.text = "\(i + 1)"
            n.font = Theme.font(10)
            n.textColor = Theme.textDim
            n.textAlignment = .center
            addSubview(n)
            numbers.append(n)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func update(byte: UInt8) {
        for (i, led) in leds.enumerated() {
            led.color = byte & UInt8(1 << i) != 0 ? Theme.functionOn : Theme.rgb(0x2A2D32)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelW: CGFloat = 90
        label.frame = CGRect(x: 0, y: 0, width: labelW, height: bounds.height)
        let slot = (bounds.width - labelW) / 8
        let d = max(10, min(slot - 10, bounds.height - 16, 30))
        for i in 0..<8 {
            let cx = labelW + slot * (CGFloat(i) + 0.5)
            leds[i].frame = CGRect(x: cx - d / 2, y: (bounds.height - d - 12) / 2, width: d, height: d)
            numbers[i].frame = CGRect(x: cx - 15, y: leds[i].frame.maxY, width: 30, height: 12)
        }
    }
}
