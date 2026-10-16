import Foundation

/// Sampling timestamps travel with the values. Display smoothing never edits them.
struct HistoryChartTiming: Equatable {
    static let window: TimeInterval = 120
    let sampledAt: [TimeInterval]
    let referenceTime: TimeInterval

    static func scrollFraction(from old: Self, samples oldValues: [Double],
                               to new: Self, samples newValues: [Double]) -> Double? {
        let delta = new.referenceTime - old.referenceTime
        guard delta.isFinite, delta > 0, delta <= 6,
              old.sampledAt.count == oldValues.count, new.sampledAt.count == newValues.count,
              oldValues.count > 1, newValues.count > 1,
              let oldLast = old.sampledAt.last,
              old.referenceTime >= oldLast, old.referenceTime - oldLast <= 0.1,
              let retainedLast = new.sampledAt.firstIndex(of: oldLast),
              retainedLast < newValues.count - 1,
              let first = new.sampledAt.first,
              let oldStart = old.sampledAt.firstIndex(of: first), oldStart <= 1 else { return nil }
        guard Array(old.sampledAt[oldStart...]) == Array(new.sampledAt[...retainedLast]),
              Array(oldValues[oldStart...]) == Array(newValues[...retainedLast]) else { return nil }
        return delta / window
    }
}

/// Quantized headroom plus eight seconds of hysteresis when reducing the scale.
struct HistoryChartScale {
    private(set) var ceiling = 8.0
    private var lowerSince: TimeInterval?
    private var previousTime: TimeInterval?
    private var primed = false

    mutating func reset() { self = Self() }

    mutating func update(peak: Double, at now: TimeInterval) -> Double {
        let peak = peak.isFinite ? max(peak, 0) : 0
        let required = max(peak <= Double.greatestFiniteMagnitude / 1.14 ? peak * 1.14 : peak, 8)
        let step = pow(10, floor(log10(required)) - 1) * 5
        let rounded = ceil(required / step) * step
        let target = rounded.isFinite ? rounded : required
        if let previousTime, now < previousTime { lowerSince = nil }
        previousTime = now
        if !primed || target > ceiling {
            ceiling = target
            primed = true
            lowerSince = nil
        } else if target <= ceiling * 0.75 {
            if lowerSince == nil { lowerSince = now }
            if now - (lowerSince ?? now) >= 8 {
                ceiling = target
                lowerSince = nil
            }
        } else {
            lowerSince = nil
        }
        return ceiling
    }
}

/// Normalized, shape-preserving cubic geometry. No moving average or peak removal.
struct HistoryChartGeometry {
    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    struct Cubic {
        let start: Point
        let control1: Point
        let control2: Point
        let end: Point

        func value(at t: Double) -> Double {
            let t = min(max(t, 0), 1), u = 1 - t
            return u * u * u * start.y + 3 * u * u * t * control1.y
                + 3 * u * t * t * control2.y + t * t * t * end.y
        }
    }

    let runs: [[Point]]
    let segments: [Cubic]
    let points: [Point]

    init(samples: [Double], timing: HistoryChartTiming?, ceiling: Double,
         leadingContext: Bool = false) {
        let times = timing?.sampledAt ?? samples.indices.map { Double($0) * 2 }
        let reference = timing?.referenceTime ?? times.last ?? 0
        guard times.count == samples.count, ceiling.isFinite, ceiling > 0,
              reference.isFinite, times.allSatisfy(\.isFinite),
              zip(times, times.dropFirst()).allSatisfy({ $0 < $1 }),
              times.last.map({ $0 <= reference }) ?? true else {
            runs = []; segments = []; points = []; return
        }
        var groups: [[Point]] = [], current: [Point] = []
        for i in samples.indices {
            let age = reference - times[i]
            let context = leadingContext && i == 0 && age <= HistoryChartTiming.window + 6
            let valid = samples[i].isFinite && age >= 0 && (age < HistoryChartTiming.window || context)
            let gap = i > 0 && times[i] - times[i - 1] > 6
            if !valid || gap {
                if !current.isEmpty { groups.append(current); current = [] }
            }
            guard valid else { continue }
            current.append(Point(x: 1 - age / HistoryChartTiming.window,
                                 y: min(max(samples[i] / ceiling, 0), 1)))
        }
        if !current.isEmpty { groups.append(current) }
        runs = groups
        points = groups.flatMap { $0 }
        segments = groups.flatMap(Self.cubics)
    }

    func value(at x: Double) -> Double? {
        guard let segment = segments.first(where: { x >= $0.start.x && x <= $0.end.x }) else {
            return points.first(where: { abs($0.x - x) < 1e-12 })?.y
        }
        return segment.value(at: (x - segment.start.x) / (segment.end.x - segment.start.x))
    }

    private static func cubics(_ p: [Point]) -> [Cubic] {
        guard p.count > 1 else { return [] }
        let h = zip(p, p.dropFirst()).map { $1.x - $0.x }
        let d = zip(p, p.dropFirst()).enumerated().map { ($0.element.1.y - $0.element.0.y) / h[$0.offset] }
        var m = [Double](repeating: 0, count: p.count)
        if p.count == 2 {
            m[0] = d[0]; m[1] = d[0]
        } else {
            for i in 1..<(p.count - 1) where d[i - 1] * d[i] > 0 {
                let w1 = 2 * h[i] + h[i - 1], w2 = h[i] + 2 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
            }
            m[0] = endpoint(h[0], h[1], d[0], d[1])
            m[p.count - 1] = endpoint(h[h.count - 1], h[h.count - 2], d[d.count - 1], d[d.count - 2])
        }
        return (0..<(p.count - 1)).map { i in
            let dx = h[i] / 3
            return Cubic(start: p[i],
                control1: Point(x: p[i].x + dx, y: p[i].y + m[i] * dx),
                control2: Point(x: p[i + 1].x - dx, y: p[i + 1].y - m[i + 1] * dx),
                end: p[i + 1])
        }
    }

    private static func endpoint(_ h0: Double, _ h1: Double, _ d0: Double, _ d1: Double) -> Double {
        let slope = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if slope * d0 <= 0 { return 0 }
        if d0 * d1 <= 0, abs(slope) > 3 * abs(d0) { return 3 * d0 }
        return slope
    }
}
