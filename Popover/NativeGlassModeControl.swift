import AppKit

private final class NativeGlassModeButton: NSButton {
    weak var modeGroup: NativeGlassModeControl?

    override func keyDown(with event: NSEvent) {
        if modeGroup?.handleKeyDown(event, from: tag) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        scrollToVisible(bounds.insetBy(dx: -2, dy: -2))
        return true
    }
}

/// Native glass buttons report intent; the footer owns selection and rollback.
/// The footer places this transparent group and its menu in one glass container.
final class NativeGlassModeControl: NSView {
    static let preferredHeight: CGFloat = 38
    private static let buttonSpacing: CGFloat = 6

    private let modes: [EnergyMode]
    private var buttons: [NativeGlassModeButton] = []
    private var selectedIndex = 0
    private var enabledModes: [EnergyMode] = []
    var onSelect: ((EnergyMode) -> Void)?

    init(modes: [EnergyMode]) {
        self.modes = modes
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Power Mode")
        for (index, mode) in modes.enumerated() {
            let button = NativeGlassModeButton(title: mode.title, target: self,
                                               action: #selector(selectionChanged(_:)))
            button.modeGroup = self
            button.tag = index
            button.setButtonType(.pushOnPushOff)
            button.allowsMixedState = false
            button.isBordered = true
            if #available(macOS 26.0, *) {
                button.bezelStyle = .glass
                button.borderShape = .capsule
            }
            button.controlSize = .large
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.toolTip = mode.title
            // Native NSButtonCell exposes the toggle's label and state. Adding
            // accessibility to its view would duplicate the actionable node.
            addSubview(button)
            buttons.append(button)
        }
        setAccessibilityChildren(buttons)
        applySelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Retain a keyboard destination during a pending request even when every
    // button is temporarily disabled. Disabled actions still fail closed.
    override var acceptsFirstResponder: Bool { true }

    var keyboardFocusView: NSView {
        if buttons.indices.contains(selectedIndex), buttons[selectedIndex].isEnabled {
            return buttons[selectedIndex]
        }
        return buttons.first(where: \.isEnabled) ?? self
    }

    override func layout() {
        super.layout()
        guard !buttons.isEmpty else { return }
        let width = (bounds.width - CGFloat(buttons.count - 1) * Self.buttonSpacing)
            / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * (width + Self.buttonSpacing),
                                  y: 0, width: width, height: bounds.height)
        }
    }

    func update(selected: EnergyMode, enabledModes: [EnergyMode]) {
        // Disabling a focused NSButton makes AppKit move focus to the window.
        // Keep it in this group while its owner confirms the pending mode.
        if let focusedIndex = buttons.firstIndex(where: { window?.firstResponder === $0 }),
           !enabledModes.contains(modes[focusedIndex]) {
            window?.makeFirstResponder(self)
        }
        let previousIndex = selectedIndex
        if let index = modes.firstIndex(of: selected) { selectedIndex = index }
        self.enabledModes = enabledModes
        applySelection()
        if window?.firstResponder === self, keyboardFocusView !== self {
            window?.makeFirstResponder(keyboardFocusView)
        }
        if previousIndex != selectedIndex {
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }

    private func applySelection() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.state = selected ? .on : .off
            button.isEnabled = enabledModes.contains(modes[index])
            if #available(macOS 26.0, *) {
                button.tintProminence = selected ? .primary : .none
            }
        }
        setAccessibilityEnabled(buttons.contains(where: \.isEnabled))
        if modes.indices.contains(selectedIndex) {
            setAccessibilityValueDescription(modes[selectedIndex].title)
        }
    }

    @objc private func selectionChanged(_ sender: NSButton) {
        sendSelection(sender.tag)
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyDown(event) { return }
        super.keyDown(with: event)
    }

    fileprivate func handleKeyDown(_ event: NSEvent, from index: Int? = nil) -> Bool {
        let currentIndex = index ?? selectedIndex
        switch event.keyCode {
        case 123: return selectAdjacentMode(direction: -1, from: currentIndex)
        case 124: return selectAdjacentMode(direction: 1, from: currentIndex)
        case 36, 76: return sendSelection(currentIndex)
        case 49 where window?.firstResponder === self: return sendSelection(selectedIndex)
        default: return false
        }
    }

    override func accessibilityPerformIncrement() -> Bool { selectAdjacentMode(direction: 1) }
    override func accessibilityPerformDecrement() -> Bool { selectAdjacentMode(direction: -1) }
    override func accessibilityPerformPress() -> Bool { sendSelection(selectedIndex) }

    private func selectAdjacentMode(direction: Int, from index: Int? = nil) -> Bool {
        let currentIndex = index ?? selectedIndex
        let candidates = modes.indices.filter { enabledModes.contains(modes[$0]) }
        let target = direction < 0
            ? candidates.last(where: { $0 < currentIndex })
            : candidates.first(where: { $0 > currentIndex })
        guard let target else { return false }
        if window?.firstResponder === self
            || (window?.firstResponder as? NSView)?.isDescendant(of: self) == true {
            window?.makeFirstResponder(buttons[target])
        }
        return sendSelection(target)
    }

    @discardableResult
    private func sendSelection(_ index: Int) -> Bool {
        // Native toggle buttons may already have changed state before action.
        // Restore the owner's value even for a repeated or rejected click.
        applySelection()
        guard modes.indices.contains(index), enabledModes.contains(modes[index]) else { return false }
        guard index != selectedIndex else { return true }
        guard let onSelect else { return false }
        onSelect(modes[index])
        return true
    }

#if DEBUG
    var selectedModeForTest: EnergyMode? {
        modes.indices.contains(selectedIndex) ? modes[selectedIndex] : nil
    }
    func selectModeForTest(_ mode: EnergyMode) {
        guard let index = modes.firstIndex(of: mode) else { return }
        sendSelection(index)
    }
#endif
}
