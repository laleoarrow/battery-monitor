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

    /// A viewport change may only age retained samples, without adding a point.
    /// Match their actual times and values before reusing the displayed scale.
    static func viewportFraction(from old: Self, samples oldValues: [Double],
                                 to new: Self, samples newValues: [Double]) -> Double? {
        let delta = new.referenceTime - old.referenceTime
        guard delta.isFinite, delta >= 0, delta <= 6,
              old.sampledAt.count == oldValues.count, new.sampledAt.count == newValues.count,
              oldValues.count > 1, newValues.count > 1,
              oldValues.allSatisfy(\.isFinite), newValues.allSatisfy(\.isFinite),
              let oldLast = old.sampledAt.last, let newLast = new.sampledAt.last,
              old.referenceTime >= oldLast, new.referenceTime >= newLast,
              [old.sampledAt, new.sampledAt].allSatisfy({ times in
                  times.allSatisfy(\.isFinite)
                      && zip(times, times.dropFirst()).allSatisfy { $0 < $1 && $1 - $0 <= 6 }
              }),
              let retainedLast = new.sampledAt.firstIndex(of: oldLast),
              let first = new.sampledAt.first,
              let oldStart = old.sampledAt.firstIndex(of: first), oldStart <= 1,
              Array(old.sampledAt[oldStart...]) == Array(new.sampledAt[...retainedLast]),
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
    struct SegmentID: Equatable {
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

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
    let segmentIDs: [SegmentID]

    private init(runs: [[Point]], segments: [Cubic], points: [Point], segmentIDs: [SegmentID]) {
        self.runs = runs
        self.segments = segments
        self.points = points
        self.segmentIDs = segmentIDs
    }

    init(samples: [Double], timing: HistoryChartTiming?, ceiling: Double,
         leadingContextCount: Int = 0) {
        let times = timing?.sampledAt ?? samples.indices.map { Double($0) * 2 }
        let reference = timing?.referenceTime ?? times.last ?? 0
        guard times.count == samples.count, ceiling.isFinite, ceiling > 0,
              reference.isFinite, times.allSatisfy(\.isFinite),
              zip(times, times.dropFirst()).allSatisfy({ $0 < $1 }),
              times.last.map({ $0 <= reference }) ?? true else {
            runs = []; segments = []; points = []; segmentIDs = []; return
        }
        var groups: [[Point]] = [], current: [Point] = []
        var timeGroups: [[TimeInterval]] = [], currentTimes: [TimeInterval] = []
        for i in samples.indices {
            let age = reference - times[i]
            let context = i < leadingContextCount && age <= HistoryChartTiming.window + 6
            let valid = samples[i].isFinite && age >= 0 && (age < HistoryChartTiming.window || context)
            let gap = i > 0 && times[i] - times[i - 1] > 6
            if !valid || gap {
                if !current.isEmpty {
                    groups.append(current); current = []
                    timeGroups.append(currentTimes); currentTimes = []
                }
            }
            guard valid else { continue }
            current.append(Point(x: 1 - age / HistoryChartTiming.window,
                                 y: context ? max(samples[i] / ceiling, 0)
                                            : min(max(samples[i] / ceiling, 0), 1)))
            currentTimes.append(times[i])
        }
        if !current.isEmpty { groups.append(current); timeGroups.append(currentTimes) }
        runs = groups
        points = groups.flatMap { $0 }
        segments = groups.flatMap(Self.cubics)
        segmentIDs = timeGroups.flatMap { times in
            zip(times, times.dropFirst()).map { SegmentID(startTime: $0, endTime: $1) }
        }
    }

    /// Target topology in the actually displayed viewport. Retained intervals
    /// keep all four visible points; new intervals use the target's bounded
    /// curve mapped to that viewport, initially outside the reveal boundary.
    func alignedStart(from previous: Self, presentedSegments: [Cubic],
                      fraction: Double, oldCeiling: Double, newCeiling: Double) -> Self? {
        guard presentedSegments.count == previous.segmentIDs.count,
              oldCeiling.isFinite, newCeiling.isFinite, fraction.isFinite,
              oldCeiling > 0, newCeiling > 0, fraction >= 0,
              fraction <= 6 / HistoryChartTiming.window else { return nil }
        func finite(_ p: Point) -> Bool { p.x.isFinite && p.y.isFinite }
        guard presentedSegments.allSatisfy({
            finite($0.start) && finite($0.control1) && finite($0.control2) && finite($0.end)
        }) else { return nil }
        let ratio = oldCeiling / newCeiling
        func rebase(_ p: Point) -> Point { Point(x: p.x - fraction, y: p.y * ratio) }
        func same(_ a: Point, _ b: Point) -> Bool {
            abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
        }
        let matches = segments.enumerated().map { index, target -> Int? in
            guard let priorIndex = previous.segmentIDs.firstIndex(of: segmentIDs[index]) else { return nil }
            let raw = previous.segments[priorIndex]
            return same(rebase(raw.start), target.start) && same(rebase(raw.end), target.end) ? priorIndex : nil
        }
        guard let first = matches.firstIndex(where: { $0 != nil }), let prior = matches[first] else { return nil }
        var shift = presentedSegments[prior].start.x - segments[first].start.x
        var scale = newCeiling / oldCeiling, largest = 0.0
        // A large raw anchor avoids amplifying presentation rounding near zero.
        // All-zero retained data has no visible Y scale to recover.
        for (index, prior) in matches.enumerated() {
            guard let prior else { continue }
            for (target, shown) in [(segments[index].start, presentedSegments[prior].start),
                                    (segments[index].end, presentedSegments[prior].end)] where target.y > largest {
                largest = target.y
                scale = shown.y / target.y
                shift = shown.x - target.x
            }
        }
        guard shift.isFinite, scale.isFinite, scale > 0 else { return nil }
        func project(_ p: Point) -> Point { Point(x: p.x + shift, y: p.y * scale) }
        var aligned: [Cubic] = [], initialRuns: [[Point]] = [], index = 0
        for run in runs {
            var anchors = run.map(project)
            for offset in 0..<max(0, run.count - 1) {
                if let prior = matches[index + offset] {
                    anchors[offset] = presentedSegments[prior].start
                    anchors[offset + 1] = presentedSegments[prior].end
                }
            }
            for offset in 0..<max(0, run.count - 1) {
                let target = segments[index]
                let shown = matches[index].map { presentedSegments[$0] }
                aligned.append(Cubic(start: anchors[offset],
                    control1: shown?.control1 ?? project(target.control1),
                    control2: shown?.control2 ?? project(target.control2), end: anchors[offset + 1]))
                index += 1
            }
            initialRuns.append(anchors)
        }
        return Self(runs: initialRuns, segments: aligned,
                    points: initialRuns.flatMap { $0 }, segmentIDs: segmentIDs)
    }

    func value(at x: Double, blendingFrom start: Self, progress: Double) -> Double? {
        guard let firstLast = start.points.last, let last = points.last else { return nil }
        let q = min(max(progress, 0), 1), shift = firstLast.x - last.x
        let targetX = min(x - shift * (1 - q), last.x)
        guard let targetY = value(at: targetX), let startY = start.value(at: targetX + shift) else { return nil }
        return startY + (targetY - startY) * q
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
