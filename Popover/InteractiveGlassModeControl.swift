import AppKit
import SwiftUI

/// Selection belongs to the footer. This model only validates intents and keeps
/// a cancellable pointer snapshot; it never performs or predicts a helper write.
final class InteractiveGlassModeModel: ObservableObject {
    struct Drag: Equatable {
        let origin: CGFloat
        let generation: Int
        let allowed: Bool
        let pressedIndex: Int?
        let start: NSPoint
    }
    struct FocusRequest: Equatable {
        let sequence: Int
        let index: Int // modes.count is the menu
    }
    let modes: [EnergyMode]
    @Published private(set) var selectedIndex = 0
    @Published private(set) var enabledModes: [EnergyMode] = []
    @Published private(set) var generation = 0
    @Published private(set) var rowWidth: CGFloat = 328
    @Published private(set) var focusRequest: FocusRequest?
    var focusedIndex: Int?
    var onSelect: ((EnergyMode) -> Void)?
    var onShowMenu: ((NSView) -> Void)?
    var onEscape: (() -> Void)?
    weak var menuAnchor: NSView?
    private var lastDrag: Drag?
    private var focusSequence = 0
    var trackWidth: CGFloat { rowWidth - 46 }
    var slotWidth: CGFloat { trackWidth / CGFloat(modes.count) }
    var selected: EnergyMode { modes[selectedIndex] }

    init(modes: [EnergyMode]) {
        precondition(!modes.isEmpty)
        self.modes = modes
    }

    func update(selected: EnergyMode, enabledModes: [EnergyMode]) {
        if self.enabledModes != enabledModes {
            cancel()
            self.enabledModes = enabledModes
        }
        if let index = modes.firstIndex(of: selected), selectedIndex != index { selectedIndex = index }
    }
    func setRowWidth(_ width: CGFloat) {
        guard width > 46, rowWidth != width else { return }
        cancel()
        rowWidth = width
    }
    func cancel() {
        generation += 1
        lastDrag = nil
    }
    func beginDrag(startX: CGFloat, startY: CGFloat = 19) -> Drag {
        let origin = CGFloat(selectedIndex) * slotWidth
        let start = NSPoint(x: startX, y: startY)
        let pressedIndex = modes.indices.first {
            labelRect($0).contains(start) && enabledModes.contains(modes[$0])
        }
        return Drag(origin: origin, generation: generation,
                    allowed: pressedIndex == selectedIndex, pressedIndex: pressedIndex, start: start)
    }
    private func labelRect(_ index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * slotWidth, y: 0, width: slotWidth, height: 38)
    }
    func remember(_ drag: Drag) { lastDrag = drag }
    var isDragging: Bool { lastDrag.map { $0.pressedIndex != nil && $0.generation == generation } ?? false }
    func cancelDragIfActive() -> Bool {
        guard isDragging else { return false }
        cancel()
        return true
    }
    func dragOrigin(translationX: CGFloat) -> CGFloat? {
        lastDrag.flatMap { origin(for: $0, translationX: translationX) }
    }
    func origin(for drag: Drag, translationX: CGFloat) -> CGFloat? {
        guard drag.allowed, drag.generation == generation, translationX.isFinite else { return nil }
        return min(max(drag.origin + translationX, 0), trackWidth - slotWidth)
    }
    @discardableResult func finishDrag(translationX: CGFloat, translationY: CGFloat = 0) -> Bool {
        guard let drag = lastDrag else { return false }
        lastDrag = nil
        guard drag.generation == generation, translationX.isFinite, translationY.isFinite else { return false }
        if !drag.allowed {
            // The parent gesture has already won over the Button. Preserve an
            // ordinary click when pointer jitter ends in its original label.
            let end = NSPoint(x: drag.start.x + translationX, y: drag.start.y + translationY)
            guard let index = drag.pressedIndex, labelRect(index).contains(end) else { return false }
            return request(index)
        }
        guard let x = origin(for: drag, translationX: translationX) else { return false }
        let candidates = modes.indices.filter { enabledModes.contains(modes[$0]) }
        guard let target = candidates.min(by: {
            abs(CGFloat($0) * slotWidth - x) < abs(CGFloat($1) * slotWidth - x)
        }) else { return false }
        return request(target)
    }
    @discardableResult func request(_ index: Int) -> Bool {
        cancel()
        guard modes.indices.contains(index), enabledModes.contains(modes[index]) else { return false }
        if focusedIndex != nil && focusedIndex != modes.count { requestFocus(index) }
        guard index != selectedIndex else { return true }
        guard let onSelect else { return false }
        onSelect(modes[index])
        return true
    }
    @discardableResult func move(_ direction: Int, from index: Int? = nil) -> Bool {
        let current = index ?? selectedIndex
        let candidates = modes.indices.filter { enabledModes.contains(modes[$0]) }
        let target = direction < 0 ? candidates.last(where: { $0 < current })
            : candidates.first(where: { $0 > current })
        guard let target else { return false }
        return request(target)
    }
    func requestFocus(_ index: Int? = nil) {
        let target = index ?? (enabledModes.contains(selected) ? selectedIndex
            : modes.firstIndex(where: enabledModes.contains))
        guard let target else { return }
        focusSequence += 1
        focusRequest = FocusRequest(sequence: focusSequence, index: target)
    }
    func showMenu() {
        cancel()
        guard let menuAnchor, menuAnchor.window != nil else { return }
        onShowMenu?(menuAnchor)
    }
}

/// A narrow AppKit lifecycle boundary around the accepted SwiftUI A2 material.
@available(macOS 26.0, *)
final class InteractiveGlassModeControl: NSView {
    static let opticalInset: CGFloat = 12
    private let model: InteractiveGlassModeModel
    private let hosting: NSHostingView<InteractiveGlassModeView>
    private var parkingFocus = false
    var onSelect: ((EnergyMode) -> Void)? {
        get { model.onSelect }
        set { model.onSelect = newValue }
    }
    var onShowMenu: ((NSView) -> Void)? {
        get { model.onShowMenu }
        set { model.onShowMenu = newValue }
    }
    var keyboardFocusView: NSView { self }
    var hasMenuFocus: Bool { containsKeyboardFocus && model.focusedIndex == model.modes.count }
    private var containsKeyboardFocus: Bool {
        window?.firstResponder === self
            || (window?.firstResponder as? NSView)?.isDescendant(of: self) == true
    }

    init(modes: [EnergyMode]) {
        model = InteractiveGlassModeModel(modes: modes)
        hosting = NSHostingView(rootView: InteractiveGlassModeView(model: model))
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 62))
        hosting.sizingOptions = []
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        model.onEscape = { [weak self] in self?.nextResponder?.cancelOperation(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(cancelInteraction),
            name: NSApplication.didResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if !parkingFocus { model.requestFocus() }
        return true
    }
    func requestMenuFocus() { model.requestFocus(model.modes.count) }
    func update(selected: EnergyMode, enabledModes: [EnergyMode]) {
        if containsKeyboardFocus, !hasMenuFocus,
           let focused = model.focusedIndex, model.modes.indices.contains(focused),
           !enabledModes.contains(model.modes[focused]) {
            parkingFocus = true
            window?.makeFirstResponder(self)
            parkingFocus = false
        }
        model.update(selected: selected, enabledModes: enabledModes)
        if window?.firstResponder === self { model.requestFocus() }
    }
    override func layout() {
        super.layout()
        model.setRowWidth(bounds.width - 2 * Self.opticalInset)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.insetBy(dx: Self.opticalInset, dy: Self.opticalInset)
            .contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    @objc func cancelInteraction() { model.cancel() }
    func cancelDragIfActive() -> Bool { model.cancelDragIfActive() }
    override func cancelOperation(_ sender: Any?) { cancelInteraction() }
    override func viewDidHide() {
        cancelInteraction()
        super.viewDidHide()
    }
    override func viewDidChangeEffectiveAppearance() {
        cancelInteraction()
        super.viewDidChangeEffectiveAppearance()
    }
    override func viewWillMove(toSuperview newSuperview: NSView?) {
        cancelInteraction()
        super.viewWillMove(toSuperview: newSuperview)
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelInteraction()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(cancelInteraction),
                name: NSWindow.didResignKeyNotification, object: window)
        }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancelInteraction(); nextResponder?.cancelOperation(nil)
        case 123: _ = model.move(-1)
        case 124: _ = model.move(1)
        case 36, 76, 49: _ = model.request(model.selectedIndex)
        default: super.keyDown(with: event)
        }
    }
#if DEBUG
    var selectedModeForTest: EnergyMode { model.selected }
    var enabledModesForTest: [EnergyMode] { model.enabledModes }
    var cancellationGenerationForTest: Int { model.generation }
    var isDraggingForTest: Bool { model.isDragging }
    func dragOriginForTest(translationX: CGFloat) -> CGFloat? { model.dragOrigin(translationX: translationX) }
    func selectModeForTest(_ mode: EnergyMode) {
        if let index = model.modes.firstIndex(of: mode) { _ = model.request(index) }
    }
    func beginDragForTest(startX: CGFloat) { model.remember(model.beginDrag(startX: startX)) }
    func endDragForTest(translationX: CGFloat) { _ = model.finishDrag(translationX: translationX) }
#endif
}

private struct InteractiveModeCapsule: Shape {
    let origin: CGFloat
    let width: CGFloat
    func path(in rect: CGRect) -> Path {
        Capsule().path(in: CGRect(x: rect.minX + origin, y: rect.minY,
                                  width: width, height: rect.height))
    }
}

private struct InteractiveModeMenuAnchor: NSViewRepresentable {
    let model: InteractiveGlassModeModel
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        model.menuAnchor = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@available(macOS 26.0, *)
private struct InteractiveGlassModeView: View {
    struct Pointer: Equatable {
        let drag: InteractiveGlassModeModel.Drag
        var translationX: CGFloat
    }
    @ObservedObject var model: InteractiveGlassModeModel
    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var pointer: Pointer?
    @FocusState private var focusedIndex: Int?
    @Namespace private var trackSpace

    // Clear restores the dark glass highlights; Regular keeps the selected
    // capsule visible against a white background in Light appearance.
    private var controlGlass: Glass { colorScheme == .dark ? .clear : .regular }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 8) {
                modeTrack
                Button { model.showMenu() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                        .contentShape(.focusEffect, Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(controlGlass.interactive(), in: Circle())
                .background(InteractiveModeMenuAnchor(model: model).allowsHitTesting(false))
                .focused($focusedIndex, equals: model.modes.count)
                .accessibilityLabel("Choose Modules")
            }
        }
        .padding(12)
        .frame(width: model.rowWidth + 24, height: 62)
        .onChange(of: focusedIndex) { _, value in model.focusedIndex = value }
        .onChange(of: model.focusRequest) { _, request in
            if let request { focusedIndex = request.index }
        }
        .onExitCommand {
            let wasDragging = pointer != nil
            model.cancel()
            if !wasDragging { model.onEscape?() }
        }
        .onDisappear { model.cancel() }
    }

    private var modeTrack: some View {
        let origin = pointer.flatMap { model.origin(for: $0.drag, translationX: $0.translationX) }
            ?? CGFloat(model.selectedIndex) * model.slotWidth
        return HStack(spacing: 0) {
            ForEach(model.modes.indices, id: \.self) { index in
                Button { _ = model.request(index) } label: {
                    Text(model.modes[index].title)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: model.slotWidth, height: 38)
                        .contentShape(Rectangle())
                        .contentShape(.focusEffect, Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!model.enabledModes.contains(model.modes[index]))
                .focused($focusedIndex, equals: index)
                .accessibilityValue(index == model.selectedIndex ? "Selected" : "Not selected")
                .accessibilityAddTraits(index == model.selectedIndex ? .isSelected : [])
                .onMoveCommand { direction in
                    if direction == .left { _ = model.move(-1, from: index) }
                    if direction == .right { _ = model.move(1, from: index) }
                }
                .onKeyPress(.return) { _ = model.request(index); return .handled }
            }
        }
        .frame(width: model.trackWidth, height: 38)
        .glassEffect(controlGlass.interactive(), in: InteractiveModeCapsule(origin: origin, width: model.slotWidth))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Power Mode")
        .coordinateSpace(name: trackSpace)
        .highPriorityGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named(trackSpace))
            .updating($pointer) { value, state, _ in
                if state == nil {
                    state = Pointer(drag: model.beginDrag(startX: value.startLocation.x,
                                                         startY: value.startLocation.y), translationX: 0)
                }
                state?.translationX = value.translation.width
                if let state { model.remember(state.drag) }
            }
            .onEnded { value in
                _ = model.finishDrag(translationX: value.translation.width,
                                     translationY: value.translation.height)
            })
    }
}
