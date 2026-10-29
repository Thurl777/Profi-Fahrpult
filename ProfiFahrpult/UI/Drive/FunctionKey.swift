import UIKit

/// Funktionstaste mit Symbol und Funktionsnummer: hell mit dunkelblauem Symbol wie die
/// Funktionssymbole der ECoS, eingeschaltet gelb.
final class FunctionKey: ECoSButton {

    private(set) var function = LocoFunction(index: 0, name: "", icon: .generic, momentary: false)
    private let iconView = UIImageView()
    private let numberLabel = UILabel()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        numberLabel.font = Theme.font(11, bold: true)
        numberLabel.isUserInteractionEnabled = false
        nameLabel.font = Theme.font(15, bold: true)
        nameLabel.textAlignment = .center
        nameLabel.isUserInteractionEnabled = false
        addSubview(iconView)
        addSubview(numberLabel)
        addSubview(nameLabel)
        style = .light
        onColor = Theme.functionKeyOn
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var isOn: Bool {
        didSet { updateContent() }
    }

    override var isEnabled: Bool {
        didSet { updateContent() }
    }

    func configure(_ function: LocoFunction, on: Bool) {
        self.function = function
        self.isOn = on
        updateContent()
    }

    private func updateContent() {
        let color: UIColor = isEnabled ? Theme.functionSymbol : Theme.functionDisabled
        let iconSize = floor(min(bounds.width, bounds.height) * 0.55)
        let img = iconSize > 8 ? FunctionIconRenderer.image(function.icon, size: iconSize, color: color) : nil
        iconView.image = img
        iconView.isHidden = img == nil
        nameLabel.isHidden = img != nil
        nameLabel.text = "F\(function.index)"
        nameLabel.textColor = color
        numberLabel.text = img != nil ? "F\(function.index)" : (function.momentary ? "M" : "")
        numberLabel.textColor = Theme.functionNumber
        accessibilityLabel = "F\(function.index) \(function.name)"
    }

    private var lastSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        iconView.frame = bounds.insetBy(dx: 4, dy: 4)
        nameLabel.frame = bounds
        numberLabel.frame = CGRect(x: 5, y: 2, width: bounds.width - 10, height: 14)
        if bounds.size != lastSize {
            lastSize = bounds.size
            updateContent()
        }
    }
}
