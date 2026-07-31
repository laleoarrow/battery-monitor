import CoreGraphics
import Foundation

/// One compressive curve drives every module, so the whole popover shares a
/// single rhythm.
enum VisualEncoding {
    static let wRef: CGFloat = 100
    static let exponent: CGFloat = 0.65
    static let speedRatio: CGFloat = 3.4
    static let thickMin: CGFloat = 4
    static let thickSpan: CGFloat = 14
    static let nodeSize: CGFloat = 36

    /// A node carries at most two pipes, so `2 × (thickMin + thickSpan)`
    /// must equal `nodeSize` or pipes will outgrow their icon. Changing
    /// either constant without the other breaks test_size_invariant_contract.
    static var thickMax: CGFloat { thickMin + thickSpan }

    /// Compressive. A linear map would flatten everything below 20 W.
    static func t(_ watts: Double) -> CGFloat {
        min(1, pow(max(CGFloat(watts), 0) / wRef, exponent))
    }

    /// Speed. Uses total input so all modules move together.
    static func multiplier(_ totalInputW: Double) -> CGFloat {
        1 + t(totalInputW) * (speedRatio - 1)
    }

    /// Width. Uses this pipe's own watts so the ratio between two pipes
    /// reflects the actual power split.
    static func thickness(_ watts: Double) -> CGFloat {
        thickMin + t(watts) * thickSpan
    }

    /// Headroom past saturation, for particle count and brightness.
    static func over(_ totalInputW: Double) -> CGFloat {
        min(1, max(0, (CGFloat(totalInputW) - wRef) / 45))
    }
}
