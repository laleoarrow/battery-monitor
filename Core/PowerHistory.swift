import Foundation

/// Fixed-size ring of recent total-input readings. At the 2 s history clock
/// this spans two minutes.
final class PowerHistory {
    let capacity: Int = 60

    private var storage: [Double]
    private var writeIndex: Int = 0
    private var filled: Int = 0

    init() {
        storage = Array(repeating: 0, count: 60)
    }

    func append(_ watts: Double) {
        storage[writeIndex] = max(watts, 0)
        writeIndex = (writeIndex + 1) % capacity
        filled = min(filled + 1, capacity)
    }

    /// Oldest first.
    var samples: [Double] {
        guard filled > 0 else { return [] }
        if filled < capacity {
            return Array(storage[0..<filled])
        }
        return Array(storage[writeIndex..<capacity]) + Array(storage[0..<writeIndex])
    }

    var peak: Double {
        samples.max() ?? 0
    }
}
