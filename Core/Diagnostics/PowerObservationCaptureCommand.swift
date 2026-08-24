#if DEBUG

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

protocol RawPowerObservationCollecting {
    func collect(
        sequence: UInt64,
        scenario: String?
    ) throws -> RawPowerObservation
}

extension PowerObservationCollector: RawPowerObservationCollecting {}

protocol PowerObservationWriting: AnyObject {
    func append(
        _ observation: RawPowerObservation
    ) throws -> PowerObservationAppendResult

    func finalize(
        termination: TraceTermination,
        terminationSignal: Int32?,
        fatalErrorCode: String?
    ) throws -> URL
}

extension PowerObservationJSONLWriter: PowerObservationWriting {}

protocol PowerObservationSleeping {
    func sleep(nanoseconds: UInt64)
}

struct SystemPowerObservationSleeper: PowerObservationSleeping {
    func sleep(nanoseconds: UInt64) {
        var request = timespec(
            tv_sec: Int(nanoseconds / 1_000_000_000),
            tv_nsec: Int(nanoseconds % 1_000_000_000)
        )
        var remainder = timespec()
        while nanosleep(&request, &remainder) != 0 {
            if errno == EINTR {
                // The signal handler only records the signal. Return to the
                // command loop immediately so it can write the interrupted
                // footer outside signal context.
                return
            }
            break
        }
    }
}

protocol PowerObservationSignalReading {
    func pendingSignal() -> Int32?
}

private var powerObservationPendingSignal: sig_atomic_t = 0

private let powerObservationSignalHandler:
    @convention(c) (Int32) -> Void = { signalNumber in
        powerObservationPendingSignal = sig_atomic_t(signalNumber)
    }

struct SystemPowerObservationSignalState:
    PowerObservationSignalReading
{
    struct Installation {
        let restoreHandlers: () -> Void

        func restore() {
            restoreHandlers()
            SystemPowerObservationSignalState.reset()
        }
    }

    func pendingSignal() -> Int32? {
        let value = Int32(powerObservationPendingSignal)
        return value == 0 ? nil : value
    }

    static func reset() {
        powerObservationPendingSignal = 0
    }

    static func install() -> Installation {
        reset()
#if canImport(Darwin)
        let previousInterrupt = Darwin.signal(
            SIGINT,
            powerObservationSignalHandler
        )
        let previousTerminate = Darwin.signal(
            SIGTERM,
            powerObservationSignalHandler
        )
        return Installation {
            _ = Darwin.signal(SIGINT, previousInterrupt)
            _ = Darwin.signal(SIGTERM, previousTerminate)
        }
#elseif canImport(Glibc)
        let previousInterrupt = Glibc.signal(
            SIGINT,
            powerObservationSignalHandler
        )
        let previousTerminate = Glibc.signal(
            SIGTERM,
            powerObservationSignalHandler
        )
        return Installation {
            _ = Glibc.signal(SIGINT, previousInterrupt)
            _ = Glibc.signal(SIGTERM, previousTerminate)
        }
#else
        return Installation {}
#endif
    }
}

struct PowerObservationCaptureEnvironment {
    let macModel: String
    let architecture: String
    let operatingSystemVersion: String
    let operatingSystemBuild: String

    static func current() -> Self {
        Self(
            macModel: systemString("hw.model") ?? "unknown",
            architecture: machineArchitecture(),
            operatingSystemVersion:
                ProcessInfo.processInfo.operatingSystemVersionString,
            operatingSystemBuild:
                systemString("kern.osversion") ?? "unknown"
        )
    }

    private static func machineArchitecture() -> String {
        var value = utsname()
        guard uname(&value) == 0 else { return "unknown" }
        var machine = value.machine
        let capacity = MemoryLayout.size(ofValue: machine)
        return withUnsafePointer(to: &machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: capacity
            ) {
                String(cString: $0)
            }
        }
    }

    private static func systemString(_ name: String) -> String? {
#if canImport(Darwin)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0,
              size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: bytes)
#else
        return nil
#endif
    }
}

struct PowerObservationCaptureCommandDependencies {
    let clock: any ContinuousNanosecondClockReading
    let collector: any RawPowerObservationCollecting
    let sleeper: any PowerObservationSleeping
    let signalState: any PowerObservationSignalReading
    let environment: PowerObservationCaptureEnvironment
    let writerFactory: (
        URL,
        PowerObservationTraceHeader
    ) throws -> any PowerObservationWriting
    let recoverPartials: (URL) throws -> [URL]

    static func live() -> Self {
        let clock = SystemContinuousNanosecondClock()
        let collector = PowerObservationCollector(
            batteryReader: AppleSmartBatteryObservationReader(
                clock: clock
            ),
            smcReader: DirectSMCObservationReader(
                clock: clock
            ),
            clock: clock
        )
        return Self(
            clock: clock,
            collector: collector,
            sleeper: SystemPowerObservationSleeper(),
            signalState: SystemPowerObservationSignalState(),
            environment: .current(),
            writerFactory: { directory, header in
                try PowerObservationJSONLWriter(
                    outputDirectory: directory,
                    header: header
                )
            },
            recoverPartials: { directory in
                try PowerObservationJSONLWriter
                    .recoverEligiblePartials(in: directory)
            }
        )
    }
}

private struct PowerObservationCaptureConfiguration {
    let scenario: String
    let durationSeconds: Int
    let intervalMilliseconds: Int
    let outputDirectory: URL
}

enum PowerObservationCaptureCommand {
    static let usageExitCode: Int32 = 64
    static let cannotCreateExitCode: Int32 = 73
    static let ioExitCode: Int32 = 74
    static let fatalExitCode: Int32 = 70

    static func run(arguments: [String]) -> Int32 {
        let signalInstallation =
            SystemPowerObservationSignalState.install()
        defer { signalInstallation.restore() }
        return run(
            arguments: arguments,
            dependencies: .live()
        )
    }

    static func run(
        arguments: [String],
        dependencies: PowerObservationCaptureCommandDependencies
    ) -> Int32 {
        let configuration: PowerObservationCaptureConfiguration
        do {
            configuration = try parse(arguments: arguments)
        } catch {
            return usageExitCode
        }

        do {
            _ = try dependencies.recoverPartials(
                configuration.outputDirectory
            )
        } catch {
            return writerFailureExitCode(error)
        }

        let started = dependencies.clock.nowContinuousNanoseconds()
        let header = PowerObservationTraceHeader(
            captureTool: "WattsonPowerObservationCapture",
            captureToolVersion: 1,
            scenario: configuration.scenario,
            requestedIntervalMilliseconds:
                configuration.intervalMilliseconds,
            requestedDurationSeconds:
                configuration.durationSeconds,
            startedContinuousNanoseconds: started,
            macModel: dependencies.environment.macModel,
            architecture: dependencies.environment.architecture,
            operatingSystemVersion:
                dependencies.environment.operatingSystemVersion,
            operatingSystemBuild:
                dependencies.environment.operatingSystemBuild
        )

        let writer: any PowerObservationWriting
        do {
            writer = try dependencies.writerFactory(
                configuration.outputDirectory,
                header
            )
        } catch {
            return writerFailureExitCode(error)
        }

        let durationNanoseconds = UInt64(
            configuration.durationSeconds
        ) * 1_000_000_000
        let intervalNanoseconds = UInt64(
            configuration.intervalMilliseconds
        ) * 1_000_000
        let deadline = started.addingReportingOverflow(
            durationNanoseconds
        ).partialValue
        var sequence: UInt64 = 0

        while true {
            if let signalNumber = dependencies.signalState.pendingSignal() {
                return finalizeInterrupted(
                    writer: writer,
                    signalNumber: signalNumber
                )
            }
            let beforeSample = dependencies.clock
                .nowContinuousNanoseconds()
            if beforeSample >= deadline {
                do {
                    _ = try writer.finalize(
                        termination: .completed,
                        terminationSignal: nil,
                        fatalErrorCode: nil
                    )
                    return 0
                } catch {
                    return writerFailureExitCode(error)
                }
            }

            let observation: RawPowerObservation
            do {
                observation = try dependencies.collector.collect(
                    sequence: sequence,
                    scenario: configuration.scenario
                )
            } catch {
                let code = fatalCode(for: error)
                do {
                    _ = try writer.finalize(
                        termination: .fatalError,
                        terminationSignal: nil,
                        fatalErrorCode: code
                    )
                    return fatalExitCode
                } catch {
                    return writerFailureExitCode(error)
                }
            }

            do {
                switch try writer.append(observation) {
                case .written:
                    sequence &+= 1
                case .fileLimitReached:
                    return ioExitCode
                }
            } catch {
                if (error as? PowerObservationEncodingError) == .failed {
                    do {
                        _ = try writer.finalize(
                            termination: .fatalError,
                            terminationSignal: nil,
                            fatalErrorCode: "encoding-failed"
                        )
                        return fatalExitCode
                    } catch {
                        return writerFailureExitCode(error)
                    }
                }

                // A write or sync failure leaves the partial file for bounded
                // recovery. Do not risk a second write through a damaged
                // stream. A no-replace collision remains EX_CANTCREAT.
                return writerFailureExitCode(error)
            }

            if let signalNumber = dependencies.signalState.pendingSignal() {
                return finalizeInterrupted(
                    writer: writer,
                    signalNumber: signalNumber
                )
            }
            dependencies.sleeper.sleep(
                nanoseconds: intervalNanoseconds
            )
        }
    }

    private static func finalizeInterrupted(
        writer: any PowerObservationWriting,
        signalNumber: Int32
    ) -> Int32 {
        do {
            _ = try writer.finalize(
                termination: .interrupted,
                terminationSignal: signalNumber,
                fatalErrorCode: nil
            )
            if signalNumber == SIGINT { return 130 }
            if signalNumber == SIGTERM { return 143 }
            return 128 + signalNumber
        } catch {
            return writerFailureExitCode(error)
        }
    }

    private static func writerFailureExitCode(
        _ error: Error
    ) -> Int32 {
        guard let writerError = error as? PowerObservationWriterError else {
            return ioExitCode
        }
        switch writerError {
        case .unsafeOutputDirectory, .outputExists, .cannotCreate:
            return cannotCreateExitCode
        case .alreadyFinalized, .writeFailed, .syncFailed,
                .renameFailed:
            return ioExitCode
        }
    }

    private static func fatalCode(for error: Error) -> String {
        guard let collectorError =
                error as? PowerObservationCollectorError else {
            return "collector-failed"
        }
        switch collectorError {
        case .batteryReaderFailed:
            return "battery-reader-failed"
        case .smcReaderFailed:
            return "smc-reader-failed"
        case .invalidObservation:
            return "collector-failed"
        }
    }

    private static func parse(
        arguments: [String]
    ) throws -> PowerObservationCaptureConfiguration {
        let filtered = arguments.filter {
            $0 != "--power-observation-capture"
        }
        var scenario: String?
        var duration = 60
        var interval = 250
        var outputDirectory: URL?
        var index = 0

        while index < filtered.count {
            let option = filtered[index]
            guard index + 1 < filtered.count else {
                throw CaptureArgumentError.invalid
            }
            let value = filtered[index + 1]
            switch option {
            case "--scenario":
                scenario = value
            case "--duration":
                guard let parsed = Int(value) else {
                    throw CaptureArgumentError.invalid
                }
                duration = parsed
            case "--interval-ms":
                guard let parsed = Int(value) else {
                    throw CaptureArgumentError.invalid
                }
                interval = parsed
            case "--output-dir":
                outputDirectory = URL(
                    fileURLWithPath: value,
                    isDirectory: true
                )
            default:
                throw CaptureArgumentError.invalid
            }
            index += 2
        }

        guard let scenario,
              isSafeScenario(scenario),
              (1...600).contains(duration),
              (100...5_000).contains(interval) else {
            throw CaptureArgumentError.invalid
        }

        let directory = outputDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("Wattson", isDirectory: true)
                .appendingPathComponent(
                    "PowerCaptures",
                    isDirectory: true
                )
        return PowerObservationCaptureConfiguration(
            scenario: scenario,
            durationSeconds: duration,
            intervalMilliseconds: interval,
            outputDirectory: directory
        )
    }

    private static func isSafeScenario(_ value: String) -> Bool {
        guard (1...48).contains(value.utf8.count) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122:
                return true
            case 45, 46, 95:
                return true
            default:
                return false
            }
        }
    }

    private enum CaptureArgumentError: Error {
        case invalid
    }
}

#endif
