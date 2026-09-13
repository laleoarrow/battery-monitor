import CoreGraphics

/// Resolve against the anchor's actual display, not the primary screen or a
/// cached NSScreen. Global screen coordinates may legitimately be negative.
struct PopoverPlacement {
    struct Display {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    let anchorFrame: CGRect
    let contentSize: CGSize
    let visibleFrame: CGRect

    /// A glass panel has no native popover arrow. Keep its transparent optical
    /// margin on the anchor's display, including displays left/below primary.
    func glassPanelFrame(margin: CGFloat) -> CGRect? {
        guard margin.isFinite, margin >= 0 else { return nil }
        let size = CGSize(width: contentSize.width + 2 * margin,
                          height: contentSize.height + 2 * margin)
        let top = min(anchorFrame.minY, visibleFrame.maxY) - 4
        guard size.width <= visibleFrame.width, size.height <= top - visibleFrame.minY else {
            return nil
        }
        let x = min(max(anchorFrame.midX - size.width / 2, visibleFrame.minX),
                    visibleFrame.maxX - size.width)
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    static func resolve(
        anchor: CGRect,
        displays: [Display],
        naturalSize: CGSize
    ) -> PopoverPlacement? {
        guard usable(anchor), naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0 else { return nil }

        let candidates = displays.filter { usable($0.frame) && usable($0.visibleFrame) }
        guard let display = candidates.max(by: {
            overlap(anchor, $0.frame) < overlap(anchor, $1.frame)
        }), overlap(anchor, display.frame) > 0 else { return nil }

        let clippedAnchor = anchor.intersection(display.frame)
        let visible = display.visibleFrame.intersection(display.frame)
        guard usable(visible), naturalSize.width <= visible.width else { return nil }
        // Leave room for NSPopover's arrow/chrome and a small bottom margin.
        // Shrink only the scrolling viewport; never scale the instruments.
        let availableHeight = min(clippedAnchor.minY, visible.maxY) - visible.minY - 24
        guard availableHeight > 0 else { return nil }
        return PopoverPlacement(
            anchorFrame: clippedAnchor,
            contentSize: CGSize(width: naturalSize.width,
                                height: min(naturalSize.height, availableHeight)),
            visibleFrame: visible
        )
    }

    private static func usable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
