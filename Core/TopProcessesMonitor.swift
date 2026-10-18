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
    private var cachedReady: (state: TopProcessesState, completedAt: TimeInterval)?

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
        if value, let cachedReady {
            let age = now() - cachedReady.completedAt
            if age >= 0, age < 10 {
                onUpdate?(cachedReady.state)
                refreshIfNeeded()
                return
            }
        }
        if value {
            cachedReady = nil
            nextRefresh = 0
        }
        // Hidden rows clear their selection, while a recent completed sample
        // can be reused when the popup opens again before its refresh deadline.
        onUpdate?(.loading)
        refreshIfNeeded()
    }

    func invalidate() {
        cachedReady = nil
        nextRefresh = 0
        generation &+= 1
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
            let completedAt = self.now()
            self.nextRefresh = completedAt + 10
            if case .ready = result {
                self.cachedReady = (result, completedAt)
            } else {
                self.cachedReady = nil
            }
            self.onUpdate?(result)
        }
    }
}
