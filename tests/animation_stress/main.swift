import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ANIMATION_STRESS_FAILED: \(message)\n".utf8))
    exit(1)
}

func keyPaths(in animation: CAAnimation) -> Set<String> {
    if let property = animation as? CAPropertyAnimation, let keyPath = property.keyPath {
        return [keyPath]
    }
    if let group = animation as? CAAnimationGroup {
        return Set((group.animations ?? []).flatMap { keyPaths(in: $0) })
    }
    return []
}

let defaultIterations = 20_000
let iterations: Int
if CommandLine.arguments.count == 1 {
    iterations = defaultIterations
} else if CommandLine.arguments.count == 2,
          let requested = Int(CommandLine.arguments[1]), requested > 0 {
    iterations = requested
} else {
    fail("usage: AnimationStress [positive-iteration-count]")
}

let controller = PopoverController()
let started = ProcessInfo.processInfo.systemUptime

for iteration in 0..<iterations {
    let reduceMotion = iteration.isMultiple(of: 2)
    controller.playEntranceAnimationForTest(reduceMotion: reduceMotion)

    guard controller.entranceAnimationCountForTest == 1 else {
        fail("iteration \(iteration): expected one keyed animation, got \(controller.entranceAnimationCountForTest)")
    }
    guard let animation = controller.entranceAnimationForTest else {
        fail("iteration \(iteration): keyed animation is missing")
    }

    let paths = keyPaths(in: animation)
    guard paths.contains("opacity") else {
        fail("iteration \(iteration): entrance animation does not fade")
    }
    guard paths.contains("transform") == !reduceMotion else {
        fail("iteration \(iteration): reduce-motion composition is wrong: \(paths.sorted())")
    }
}

controller.stopEntranceAnimationForTest()
guard controller.entranceAnimationCountForTest == 0 else {
    fail("final removal left \(controller.entranceAnimationCountForTest) animation(s)")
}

let elapsed = ProcessInfo.processInfo.systemUptime - started
print(String(format: "ANIMATION_STRESS_PASSED iterations=%d elapsed=%.3fs", iterations, elapsed))
