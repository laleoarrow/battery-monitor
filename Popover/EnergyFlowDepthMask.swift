import CoreGraphics
import Foundation

/// Occlusion in section coordinates: x right, y down, positive z forward.
/// An immutable map owned by its prepared motion; shared by both appearances.
final class EnergyFlowDepthMask {
    let scale: CGFloat
    private let bounds: CGSize
    private let pixelWidth: Int
    private let depths: [Float]
    private let edgeWidth: CGFloat = 0.25

    init?(frontDepth: (CGPoint) -> CGFloat?, bounds: CGSize, scale: CGFloat = 2,
          isCancelled: () -> Bool = { false }) {
        precondition(bounds.width > 0 && bounds.height > 0 && scale > 0)
        self.bounds = bounds
        self.scale = scale
        pixelWidth = Int(ceil(bounds.width * scale))
        let pixelHeight = Int(ceil(bounds.height * scale))
        guard !isCancelled() else { return nil }
        var samples = [Float](repeating: -.infinity, count: pixelWidth * pixelHeight)
        for y in 0..<pixelHeight {
            guard !isCancelled() else { return nil }
            for x in 0..<pixelWidth {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale,
                                    y: (CGFloat(y) + 0.5) / scale)
                if let depth = frontDepth(point), depth.isFinite {
                    samples[y * pixelWidth + x] = Float(depth)
                }
            }
        }
        guard !isCancelled() else { return nil }
        depths = samples
    }

    /// The frame includes the entire halo. Sphere depth applies inside the body;
    /// outside it the halo is compared at the sphere centre's depth.
    func headMask(frame: CGRect, center: CGPoint, z: CGFloat, radius: CGFloat) -> CGImage {
        precondition(radius >= 0)
        let radiusSquared = radius * radius
        return image(frame: frame) { point in
            let dx = point.x - center.x, dy = point.y - center.y
            let distanceSquared = dx * dx + dy * dy
            return z + sqrt(max(0, radiusSquared - distanceSquared))
        }
    }

    /// Call for each consecutive valid history segment, never across a missing
    /// sample. Each pixel uses its own nearest projected t and interpolated z.
    /// Mask the halo and body together after their compositing/blur operations.
    func tailMask(frame: CGRect, from: CGPoint, to: CGPoint,
                  fromZ: CGFloat, toZ: CGFloat, radius: CGFloat) -> CGImage {
        precondition(radius >= 0)
        let dx = to.x - from.x, dy = to.y - from.y
        let lengthSquared = dx * dx + dy * dy
        let radiusSquared = radius * radius
        return image(frame: frame) { point in
            let t: CGFloat
            if lengthSquared > 1e-12 {
                t = min(1, max(0, ((point.x - from.x) * dx + (point.y - from.y) * dy)
                                   / lengthSquared))
            } else {
                // A segment parallel to the view direction projects to one point.
                // Its nearest visible end is the one with the greater z.
                t = toZ > fromZ ? 1 : 0
            }
            let nearestX = from.x + t * dx, nearestY = from.y + t * dy
            let offsetX = point.x - nearestX, offsetY = point.y - nearestY
            let distanceSquared = offsetX * offsetX + offsetY * offsetY
            return fromZ + t * (toZ - fromZ)
                + sqrt(max(0, radiusSquared - distanceSquared))
        }
    }

    private func image(frame: CGRect, fragmentDepth: (CGPoint) -> CGFloat) -> CGImage {
        precondition(frame.width > 0 && frame.height > 0)
        let width = Int(ceil(frame.width * scale)), height = Int(ceil(frame.height * scale))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        // Row zero is the frame's minimum y. No CGContext transform or image
        // flip is applied: the caller's section/layer coordinates already run down.
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: frame.minX + (CGFloat(x) + 0.5) * frame.width / CGFloat(width),
                                    y: frame.minY + (CGFloat(y) + 0.5) * frame.height / CGFloat(height))
                let opacity: CGFloat
                if let pipeZ = pipeDepth(at: point) {
                    // Soften only on the visible side. A fragment behind the
                    // pipe never leaks through, even when it belongs to a halo.
                    let t = min(1, max(0, (fragmentDepth(point) - pipeZ) / edgeWidth))
                    opacity = t * t * (3 - 2 * t)
                } else {
                    opacity = 1
                }
                let alpha = UInt8((opacity * 255).rounded())
                let index = (y * width + x) * 4
                // Premultiplied white: CALayer.mask consumes this alpha, not RGB.
                rgba[index] = alpha
                rgba[index + 1] = alpha
                rgba[index + 2] = alpha
                rgba[index + 3] = alpha
            }
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        return CGImage(width: width, height: height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo,
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func pipeDepth(at point: CGPoint) -> CGFloat? {
        guard point.x >= 0, point.y >= 0,
              point.x < bounds.width, point.y < bounds.height else { return nil }
        let x = Int(floor(point.x * scale)), y = Int(floor(point.y * scale))
        let depth = depths[y * pixelWidth + x]
        return depth.isFinite ? CGFloat(depth) : nil
    }
}
