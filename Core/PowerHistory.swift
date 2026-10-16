import Foundation

/// Fixed-size ring of total-input readings from the last two minutes.
/// The time bound still applies when sampling slows down or stops.
final class PowerHistory {
    let capacity: Int = 60
    private static let windowDuration: TimeInterval = 120

    private var storage: [Double]
    private var sampledAt: [TimeInterval]
    private var writeIndex: Int = 0
    private var filled: Int = 0
    private var cachedPresentation: (samples: [Double], peak: Double, timing: HistoryChartTiming)?
    private let clock: () -> TimeInterval
#if DEBUG
    private(set) var presentationMaterializationCountForTest = 0
#endif

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        storage = Array(repeating: 0, count: 60)
        sampledAt = Array(repeating: 0, count: 60)
    }

    func append(_ watts: Double) {
        guard watts.isFinite else { return }
        let now = clock()
        expireReadings(at: now)
        storage[writeIndex] = max(watts, 0)
        sampledAt[writeIndex] = now
        writeIndex = (writeIndex + 1) % capacity
        filled = min(filled + 1, capacity)
        cachedPresentation = nil
    }

    /// A sleep gap is not part of the two-minute sampling window. Keeping the
    /// pre-sleep ring would mislabel old readings as recent after wake.
    func reset() {
        writeIndex = 0
        filled = 0
        cachedPresentation = nil
    }

    /// Oldest first.
    var samples: [Double] {
        presentation.samples
    }

    private func materialized(_ values: [Double]) -> [Double] {
        guard filled > 0 else { return [] }
        let oldest = (writeIndex - filled + capacity) % capacity
        let end = oldest + filled
        if end <= capacity {
            return Array(values[oldest..<end])
        }
        return Array(values[oldest..<capacity]) + Array(values[0..<(end - capacity)])
    }

    private func expireReadings(at now: TimeInterval) {
        while filled > 0 {
            let oldest = (writeIndex - filled + capacity) % capacity
            guard now - sampledAt[oldest] >= Self.windowDuration else { break }
            filled -= 1
            cachedPresentation = nil
        }
    }

    /// The popover needs both values together. Deriving the peak from this
    /// materialized sequence avoids building the wrapped array a second time
    /// on every presentation refresh.
    var presentation: (samples: [Double], peak: Double) {
        let frame = chartPresentation
        return (frame.samples, frame.peak)
    }

    /// Keep the normal sampling cadence stable; after a gap, render the readings'
    /// actual age while retaining the materialized values and timestamps.
    var chartPresentation: (samples: [Double], peak: Double, timing: HistoryChartTiming) {
        let now = clock()
        expireReadings(at: now)
        if let cachedPresentation {
            guard let latestSample = cachedPresentation.timing.sampledAt.last,
                  now - latestSample > 6 else { return cachedPresentation }
            return (samples: cachedPresentation.samples, peak: cachedPresentation.peak,
                    timing: HistoryChartTiming(sampledAt: cachedPresentation.timing.sampledAt,
                                               referenceTime: now))
        }
        let samples = materialized(storage)
        let presentation = (samples: samples, peak: samples.max() ?? 0,
                            timing: HistoryChartTiming(sampledAt: materialized(sampledAt), referenceTime: now))
        cachedPresentation = presentation
#if DEBUG
        presentationMaterializationCountForTest += 1
#endif
        return presentation
    }

    var peak: Double {
        presentation.peak
    }
}
