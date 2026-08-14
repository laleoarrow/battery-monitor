import AppKit

/// Motion-free power-mode chooser used when macOS Reduce Motion is enabled.
/// AppKit owns all drawing; this class only keeps the three native segments
/// equal and reports user intent. The footer owns confirmation and rollback.
final class NativeModeSegmentedControl: NSSegmentedControl {
    static let preferredHeight: CGFloat = 30

    private let modes: [EnergyMode]
    private var enabledModes: [Bool]

    var onSelect: ((EnergyMode) -> Void)?

    init(modes: [EnergyMode]) {
        self.modes = modes
        enabledModes = Array(repeating: true, count: modes.count)
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: PopoverStyle.contentWidth,
                                 height: Self.preferredHeight))

        segmentCount = modes.count
        trackingMode = .selectOne
        segmentStyle = .automatic
        segmentDistribution = .fillEqually
        controlSize = .regular
        font = .systemFont(ofSize: 11, weight: .regular)
        focusRingType = .default
        target = self
        action = #selector(selectionChanged)

        for (index, mode) in modes.enumerated() {
            setLabel(mode.title, forSegment: index)
            setToolTip(mode.title, forSegment: index)
        }
        selectedSegment = modes.isEmpty ? -1 : 0
        configureAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool {
        enabledModes.contains(true)
    }

    func update(selected: EnergyMode, enabledModes available: [EnergyMode]) {
        enabledModes = modes.map(available.contains)
        for index in modes.indices {
            setEnabled(enabledModes[index], forSegment: index)
        }
        isEnabled = enabledModes.contains(true)

        if let index = modes.firstIndex(of: selected) {
            let changed = selectedSegment != index
            selectedSegment = index
            updateAccessibilityValue(announce: changed)
        } else {
            updateAccessibilityValue(announce: false)
        }
    }

    @objc private func selectionChanged() {
        sendSelection(selectedSegment, announce: false)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            if selectAdjacentMode(direction: -1) { return }
        case 124:
            if selectAdjacentMode(direction: 1) { return }
        case 36, 49, 76:
            sendSelection(selectedSegment, announce: false)
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func accessibilityPerformIncrement() -> Bool {
        selectAdjacentMode(direction: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        selectAdjacentMode(direction: -1)
    }

    override func accessibilityPerformPress() -> Bool {
        guard enabledModes.indices.contains(selectedSegment),
              enabledModes[selectedSegment] else { return false }
        return sendSelection(selectedSegment, announce: false)
    }

    private func configureAccessibility() {
        setAccessibilityLabel("Power Mode")
        cell?.setAccessibilityLabel("Power Mode")
        updateAccessibilityValue(announce: false)
    }

    private func updateAccessibilityValue(announce: Bool) {
        setAccessibilityEnabled(enabledModes.contains(true))
        guard modes.indices.contains(selectedSegment) else { return }
        setAccessibilityValueDescription(modes[selectedSegment].title)
        cell?.setAccessibilityValueDescription(modes[selectedSegment].title)
        if announce {
            if let cell {
                NSAccessibility.post(element: cell, notification: .valueChanged)
            } else {
                NSAccessibility.post(element: self, notification: .valueChanged)
            }
        }
    }

    @discardableResult
    private func selectAdjacentMode(direction: Int) -> Bool {
        let candidates = enabledModes.indices.filter { enabledModes[$0] }
        let target = direction < 0
            ? candidates.last(where: { $0 < selectedSegment })
            : candidates.first(where: { $0 > selectedSegment })
        guard let target else { return false }
        return sendSelection(target, announce: true)
    }

    @discardableResult
    private func sendSelection(_ index: Int, announce: Bool) -> Bool {
        guard enabledModes.indices.contains(index), enabledModes[index] else { return false }
        selectedSegment = index
        updateAccessibilityValue(announce: announce)
        onSelect?(modes[index])
        return true
    }

#if DEBUG
    var selectedModeForTest: EnergyMode? {
        modes.indices.contains(selectedSegment) ? modes[selectedSegment] : nil
    }
    func selectModeForTest(_ mode: EnergyMode) {
        guard let index = modes.firstIndex(of: mode) else { return }
        sendSelection(index, announce: false)
    }
#endif
}
