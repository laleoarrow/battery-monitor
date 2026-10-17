import Foundation

/// Shares the popover's display clock. A closed or disabled module never polls.
final class TopProcessesMonitor {
    typealias Read = (@escaping (TopProcessesState) -> Void) -> Void

    var onUpdate: ((TopProcessesState) -> Void)?
    private let read: Read
    private let now: () -> TimeInterval
    private var active = false
    private var generation: UInt = 0
    private var inFlight = false
    private var nextRefresh: TimeInterval = 0

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         read: @escaping Read = { completion in
             DispatchQueue.global(qos: .utility).async {
                 let result = HelperClient.topProcesses()
                 DispatchQueue.main.async { completion(result) }
             }
         }) {
        self.now = now
        self.read = read
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        generation &+= 1
        nextRefresh = 0
        // Clear the previous opening's readings, including the cached popup.
        onUpdate?(.loading)
        refreshIfNeeded()
    }

    func refreshIfNeeded() {
        guard active, !inFlight, now() >= nextRefresh else { return }
        inFlight = true
        let requestGeneration = generation
        read { [weak self] result in
            guard let self else { return }
            self.inFlight = false
            guard self.active, self.generation == requestGeneration else {
                // Reopening waits for the bounded old request before starting
                // fresh work, so rapid toggles cannot accumulate helper reads.
                self.refreshIfNeeded()
                return
            }
            self.nextRefresh = self.now() + 10
            self.onUpdate?(result)
        }
    }
}
