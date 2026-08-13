import Foundation

/// Fixed-size ring of recent total-input readings. At the 2 s history clock
/// this spans two minutes.
final class PowerHistory {
    let capacity: Int = 60

    private var storage: [Double]
    private var writeIndex: Int = 0
    private var filled: Int = 0
    private var cachedPresentation: (samples: [Double], peak: Double)?
#if DEBUG
    private(set) var presentationMaterializationCountForTest = 0
#endif

    init() {
        storage = Array(repeating: 0, count: 60)
    }

    func append(_ watts: Double) {
        guard watts.isFinite else { return }
        storage[writeIndex] = max(watts, 0)
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

    private func materializedSamples() -> [Double] {
        guard filled > 0 else { return [] }
        if filled < capacity {
            return Array(storage[0..<filled])
        }
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }

    /// The popover needs both values together. Deriving the peak from this
    /// materialized sequence avoids building the wrapped array a second time
    /// on every presentation refresh.
    var presentation: (samples: [Double], peak: Double) {
        if let cachedPresentation { return cachedPresentation }
        let samples = materializedSamples()
        let presentation = (samples: samples, peak: samples.max() ?? 0)
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
