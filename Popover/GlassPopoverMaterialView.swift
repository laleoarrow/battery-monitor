import AppKit
import SwiftUI

/// One continuous outline lets the system refract the arrow and body together.
/// NSGlassEffectView only exposes rounded rectangles; masking one clips its edge.
struct GlassPopoverShape: Shape {
    static let cornerRadius: CGFloat = 26
    static let arrowHalfWidth: CGFloat = 12
    var arrowX: CGFloat

    static func clampedArrowX(_ x: CGFloat, width: CGFloat) -> CGFloat {
        let edge = cornerRadius + arrowHalfWidth
        return min(max(x, edge), width - edge)
    }

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + PopoverPlacement.glassArrowHeight
        let radius = Self.cornerRadius
        let center = rect.minX + Self.clampedArrowX(arrowX, width: rect.width)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: top))
        path.addLine(to: CGPoint(x: center - Self.arrowHalfWidth, y: top))
        path.addCurve(to: CGPoint(x: center - 2, y: rect.minY + 2),
                      control1: CGPoint(x: center - 8, y: top),
                      control2: CGPoint(x: center - 4, y: rect.minY + 2))
        path.addCurve(to: CGPoint(x: center, y: rect.minY),
                      control1: CGPoint(x: center - 1, y: rect.minY + 1),
                      control2: CGPoint(x: center - 1, y: rect.minY))
        path.addCurve(to: CGPoint(x: center + 2, y: rect.minY + 2),
                      control1: CGPoint(x: center + 1, y: rect.minY),
                      control2: CGPoint(x: center + 1, y: rect.minY + 1))
        path.addCurve(to: CGPoint(x: center + Self.arrowHalfWidth, y: top),
                      control1: CGPoint(x: center + 4, y: rect.minY + 2),
                      control2: CGPoint(x: center + 8, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top),
                    tangent2End: CGPoint(x: rect.maxX, y: top + radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.minX, y: top + radius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: top),
                    tangent2End: CGPoint(x: rect.minX + radius, y: top), radius: radius)
        path.closeSubpath()
        return path
    }

    func appKitPath(in rect: CGRect) -> CGPath {
        path(in: rect).applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                                 tx: 0, ty: rect.minY + rect.maxY)).cgPath
    }
}

@available(macOS 26.0, *)
final class GlassPopoverMaterialView: NSHostingView<AnyView> {
    let style: NSGlassEffectView.Style
    private(set) var arrowX: CGFloat

    init(frame: NSRect, style: NSGlassEffectView.Style) {
        self.style = style
        arrowX = frame.width / 2
        super.init(rootView: Self.material(style: style, arrowX: arrowX))
        sizingOptions = []
        self.frame = frame
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @available(*, unavailable)
    required init(rootView: AnyView) { fatalError("Use init(frame:style:)") }

    func point(to x: CGFloat) {
        let clamped = GlassPopoverShape.clampedArrowX(x, width: bounds.width)
        guard arrowX != clamped else { return }
        arrowX = clamped
        rootView = Self.material(style: style, arrowX: arrowX)
    }

    private static func material(style: NSGlassEffectView.Style, arrowX: CGFloat) -> AnyView {
        AnyView(Color.clear
            .glassEffect(style == .clear ? .clear : .regular, in: GlassPopoverShape(arrowX: arrowX))
            .allowsHitTesting(false)
            .accessibilityHidden(true))
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
