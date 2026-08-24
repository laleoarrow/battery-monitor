import Foundation
import XCTest
@testable import Wattson

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class PowerObservationCaptureTests: XCTestCase {
    func testDirectSMCReaderAttemptsPDTRPSTRPPBRInOrderOnOneConnection() throws {
        let connection = RecordingSMCConnection(results: [
            "PDTR": presentSMCResult(80),
            "PSTR": presentSMCResult(40),
            "PPBR": presentSMCResult(5),
        ])
        let opener = RecordingSMCOpener(connection: connection)
        let observation = try DirectSMCObservationReader(
            backend: opener,
            clock: IncrementingClock()
        ).readObservation()

        XCTAssertEqual(connection.requestedKeys, ["PDTR", "PSTR", "PPBR"])
        XCTAssertEqual(opener.openCount, 1)
        XCTAssertEqual(connection.closeCount, 1)
        XCTAssertEqual(observation.keys.map(\.key), ["PDTR", "PSTR", "PPBR"])
    }

    func testDirectSMCReaderContinuesAfterSingleKeyFailure() throws {
        let connection = RecordingSMCConnection(results: [
            "PDTR": presentSMCResult(90),
            "PSTR": DirectSMCRawKeyResult(
                status: .valueReadFailed,
                dataTypeFourCC: "flt ",
                rawBytes: nil,
                decodedWatts: nil,
                ioReturn: -1,
                validationIssue: "fixture read failure"
            ),
            "PPBR": presentSMCResult(7),
        ])
        let observation = try DirectSMCObservationReader(
            backend: RecordingSMCOpener(connection: connection),
            clock: IncrementingClock()
        ).readObservation()

        XCTAssertEqual(connection.requestedKeys, ["PDTR", "PSTR", "PPBR"])
        XCTAssertEqual(observation.key("PSTR")?.status, .valueReadFailed)
        XCTAssertEqual(observation.key("PPBR")?.decodedWatts, 7)
    }

    func testDirectSMCReaderPreservesRawBytesDataTypeAndDecodedValue() throws {
        let connection = RecordingSMCConnection(results: [
            "PDTR": DirectSMCRawKeyResult(
                status: .present,
                dataTypeFourCC: "flt ",
                rawBytes: [0x00, 0x00, 0xF0, 0x42],
                decodedWatts: 120,
                ioReturn: nil,
                validationIssue: nil
            ),
            "PSTR": presentSMCResult(42),
            "PPBR": presentSMCResult(3),
        ])
        let observation = try DirectSMCObservationReader(
            backend: RecordingSMCOpener(connection: connection),
            clock: IncrementingClock()
        ).readObservation()
        let pdtr = try XCTUnwrap(observation.key("PDTR"))

        XCTAssertEqual(pdtr.dataTypeFourCC, "flt ")
        XCTAssertEqual(pdtr.rawBytesHex, "0000F042")
        XCTAssertEqual(pdtr.decodedWatts, 120)

        XCTAssertEqual(
            DirectSMCValueDecoder.decodeWatts(
                dataTypeFourCC: "flt ",
                rawBytes: littleEndianFloatBytes(-12.5)
            ),
            -12.5
        )
        XCTAssertEqual(
            DirectSMCValueDecoder.decodeWatts(
                dataTypeFourCC: "flt ",
                rawBytes: littleEndianFloatBytes(1_500)
            ),
            1_500
        )
        XCTAssertEqual(
            DirectSMCValueDecoder.decodeWatts(
                dataTypeFourCC: "sp78",
                rawBytes: [0xFF, 0x80]
            ),
            -0.5
        )
        XCTAssertEqual(
            DirectSMCValueDecoder.decodeWatts(
                dataTypeFourCC: "sp96",
                rawBytes: [0xFF, 0xC0]
            ),
            -1
        )
    }

    func testCollectorUsesSyntheticReadersWithoutRealHardware() throws {
        let capture = try interval(10, 20)
        let rawBattery = SyntheticBatterySnapshotReader(
            snapshot: AppleSmartBatteryRawSnapshot(
                servicePresent: true,
                properties: [
                    "CurrentCapacity": NSNumber(value: 50),
                    "MaxCapacity": NSNumber(value: 100),
                    "ExternalConnected": NSNumber(value: true),
                    "IsCharging": NSNumber(value: true),
                    "Voltage": NSNumber(value: 12_000),
                    "InstantAmperage": NSNumber(value: 1_000),
                    "Amperage": NSNumber(value: 900),
                    "PowerTelemetryData": [
                        "SystemPowerIn": NSNumber(value: 50_000),
                        "SystemLoad": NSNumber(value: 38_000),
                        "BatteryPower": NSNumber(value: 12_000),
                        "SystemVoltageIn": NSNumber(value: 20_000),
                        "SystemCurrentIn": NSNumber(value: 2_500),
                    ],
                    "AdapterDetails": [
                        "Watts": NSNumber(value: 140),
                        "AdapterVoltage": NSNumber(value: 28_000),
                        "Current": NSNumber(value: 5_000),
                    ],
                    "PowerOutDetails": [[
                        "Watts": NSNumber(value: 5_000),
                        "PDPowermW": NSNumber(value: 7_000),
                        "PortIndex": NSNumber(value: 1),
                    ]],
                ]
            )
        )
        let batteryReader = AppleSmartBatteryObservationReader(
            backend: rawBattery,
            clock: SequenceClock([10, 20])
        )
        let collector = PowerObservationCollector(
            batteryReader: batteryReader,
            smcReader: FixedSMCReader(
                value: .canonicalFixtureMissing(capture: capture)
            ),
            clock: SequenceClock([0, 30, 40])
        )
        let observation = try collector.collect(
            sequence: 4,
            scenario: "synthetic"
        )

        XCTAssertEqual(observation.sequence, 4)
        XCTAssertEqual(observation.scenario, "synthetic")
        XCTAssertEqual(observation.battery.servicePresence, .present)
        XCTAssertEqual(
            observation.battery.adapterCapability.ratedWatts.kind,
            .capability
        )
        XCTAssertEqual(
            observation.battery.adapterCapability.ratedWatts.watts,
            140
        )
        XCTAssertEqual(
            observation.battery.deviceOutput.measuredTotalWatts.watts,
            5
        )
        XCTAssertEqual(
            observation.battery.deviceOutput.ports.first?.pdPowerRaw.watts,
            nil
        )
        XCTAssertEqual(observation.smc.connectionStatus, .serviceUnavailable)
        XCTAssertEqual(
            observation.evidence.batteryVoltageTimesCurrent.watts,
            12
        )
        XCTAssertEqual(
            observation.evidence.systemVoltageTimesCurrent.watts,
            50
        )
        XCTAssertEqual(
            observation.evidence.balances.first?.residualWatts,
            0
        )

        let integerReader = AppleSmartBatteryObservationReader(
            backend: SyntheticBatterySnapshotReader(
                snapshot: AppleSmartBatteryRawSnapshot(
                    servicePresent: true,
                    properties: [
                        "CurrentCapacity": NSNumber(
                            value: UInt32.max
                        ),
                        "MaxCapacity": NSNumber(
                            value: UInt64.max
                        ),
                        "InstantAmperage": NSNumber(
                            value: UInt32.max
                        ),
                        "Amperage": NSNumber(
                            value: UInt64.max
                        ),
                        "PowerTelemetryData": [
                            "SystemLoad": NSNumber(
                                value: UInt32.max
                            ),
                            "BatteryPower": NSNumber(
                                value: UInt32.max
                            ),
                        ],
                    ]
                )
            ),
            clock: SequenceClock([50, 60])
        )
        let exactIntegers = try integerReader.readObservation()
        XCTAssertEqual(
            exactIntegers.currentCapacity.value,
            Int64(UInt32.max)
        )
        XCTAssertEqual(
            exactIntegers.instantAmperageMilliamps.value,
            -1
        )
        XCTAssertEqual(
            exactIntegers.averageAmperageMilliamps.value,
            -1
        )
        XCTAssertEqual(
            exactIntegers.powerTelemetry.systemLoad.rawInteger,
            Int64(UInt32.max)
        )
        XCTAssertEqual(
            exactIntegers.powerTelemetry.systemLoad.watts,
            Double(UInt32.max) / 1_000
        )
        XCTAssertEqual(
            exactIntegers.powerTelemetry.batteryPower.rawInteger,
            Int64(UInt32.max)
        )
        XCTAssertEqual(
            exactIntegers.powerTelemetry.batteryPower.watts,
            Double(UInt32.max) / 1_000
        )
        XCTAssertEqual(
            exactIntegers.maxCapacity.presence,
            .invalid
        )
        XCTAssertNil(exactIntegers.maxCapacity.value)
    }

    func testCollectorStartsBatteryAndSMCReadsIndependently() throws {
        let batteryStarted = DispatchSemaphore(value: 0)
        let smcStarted = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let capture = try interval(0, 1)
        let battery = BlockingBatteryReader(
            started: batteryStarted,
            release: release,
            value: .canonicalFixtureMissing(capture: capture)
        )
        let smc = BlockingSMCReader(
            started: smcStarted,
            release: release,
            value: .canonicalFixtureMissing(capture: capture)
        )
        let collector = PowerObservationCollector(
            batteryReader: battery,
            smcReader: smc,
            clock: SequenceClock([0, 2, 3])
        )
        let finished = expectation(description: "collector finished")
        let result = LockedResult<RawPowerObservation>()
        DispatchQueue.global().async {
            result.store(Result {
                try collector.collect(sequence: 0, scenario: nil)
            })
            finished.fulfill()
        }

        XCTAssertEqual(batteryStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(smcStarted.wait(timeout: .now() + 1), .success)
        release.signal()
        release.signal()
        wait(for: [finished], timeout: 2)
        _ = try XCTUnwrap(result.load()).get()
    }

    func testCollectorDoesNotConstructOrMutatePowerSnapshot() throws {
        let capture = try interval(0, 1)
        let observation = try PowerObservationCollector(
            batteryReader: FixedBatteryReader(
                value: .canonicalFixtureMissing(capture: capture)
            ),
            smcReader: FixedSMCReader(
                value: .canonicalFixtureMissing(capture: capture)
            ),
            clock: SequenceClock([0, 2, 3])
        ).collect(sequence: 0, scenario: nil)
        let data = try sortedEncoder().encode(observation)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("\"state\""))
        XCTAssertFalse(json.contains("\"confidence\""))
        XCTAssertFalse(json.contains("\"selectedSource\""))
        XCTAssertEqual(observation.schemaVersion, 1)
    }

    func testCollectorRecordsBatteryAndSMCCaptureSkew() throws {
        let batteryCapture = try interval(
            100_000_000,
            200_000_000
        )
        let missingBattery = AppleSmartBatteryObservation
            .canonicalFixtureMissing(capture: batteryCapture)
        let battery = AppleSmartBatteryObservation(
            servicePresence: .present,
            capture: batteryCapture,
            currentCapacity: missingBattery.currentCapacity,
            maxCapacity: missingBattery.maxCapacity,
            externalConnected: missingBattery.externalConnected,
            isCharging: missingBattery.isCharging,
            voltageMillivolts: missingBattery.voltageMillivolts,
            instantAmperageMilliamps:
                missingBattery.instantAmperageMilliamps,
            averageAmperageMilliamps:
                missingBattery.averageAmperageMilliamps,
            powerTelemetry: missingBattery.powerTelemetry,
            adapterCapability: missingBattery.adapterCapability,
            deviceOutput: missingBattery.deviceOutput
        )
        let smc = try SMCObservation(
            connectionStatus: .opened,
            connectionCapture: try interval(0, 800_000_000),
            keys: [
                smcKey("PDTR", .smcPDTR, 80, try interval(0, 10_000_000)),
                smcKey("PSTR", .smcPSTR, 60, try interval(750_000_000, 760_000_000)),
                smcKey("PPBR", .smcPPBR, 5, try interval(400_000_000, 410_000_000)),
            ]
        )
        let observation = try PowerObservationCollector(
            batteryReader: FixedBatteryReader(value: battery),
            smcReader: FixedSMCReader(value: smc),
            clock: SequenceClock([0, 800_000_000, 800_000_000])
        ).collect(sequence: 0, scenario: nil)

        XCTAssertEqual(observation.evidence.timing.smcKeySkewMilliseconds, 750)
        XCTAssertEqual(
            observation.evidence.timing
                .batteryMidpointMinusSMCMidpointMilliseconds,
            -250
        )
        XCTAssertEqual(
            observation.evidence.timing.absoluteBatterySMCSkewMilliseconds,
            250
        )
    }

    func testTelemetryFreezeTrackerReportsChangedThenUnchangedDuration() throws {
        var tracker = TelemetryFreezeTracker()
        let first = try tracker.observe(
            updateToken: "token-a",
            evaluatedAtContinuousNanoseconds: 1_000_000_000
        )
        let second = try tracker.observe(
            updateToken: "token-a",
            evaluatedAtContinuousNanoseconds: 31_000_000_000
        )

        XCTAssertEqual(first.assessment, .changed)
        XCTAssertEqual(second.assessment, .unchanged)
        XCTAssertEqual(second.unchangedForMilliseconds, 30_000)
        XCTAssertEqual(second.basis, .derivedUpdateToken)

        let telemetry: [String: Any] = [
            "SystemPowerIn": NSNumber(value: 50_000),
            "SystemLoad": NSNumber(value: 38_000),
            "BatteryPower": NSNumber(value: 12_000),
            "SystemVoltageIn": NSNumber(value: 20_000),
            "SystemCurrentIn": NSNumber(value: 2_500),
        ]
        let valid = AppleSmartBatteryRawSnapshot(
            servicePresent: true,
            properties: ["PowerTelemetryData": telemetry]
        )
        let reader = AppleSmartBatteryObservationReader(
            backend: SequenceBatterySnapshotReader([
                valid,
                AppleSmartBatteryRawSnapshot(
                    servicePresent: false,
                    properties: [:]
                ),
                valid,
                AppleSmartBatteryRawSnapshot(
                    servicePresent: true,
                    properties: [:]
                ),
                valid,
                AppleSmartBatteryRawSnapshot(
                    servicePresent: true,
                    properties: ["PowerTelemetryData": "invalid"]
                ),
                valid,
            ]),
            clock: IncrementingClock()
        )

        XCTAssertEqual(
            try reader.readObservation()
                .powerTelemetry.freshness.assessment,
            .changed
        )
        XCTAssertEqual(
            try reader.readObservation().servicePresence,
            .missing
        )
        let afterServiceGap = try reader.readObservation()
            .powerTelemetry.freshness
        XCTAssertEqual(afterServiceGap.assessment, .changed)
        XCTAssertEqual(afterServiceGap.unchangedForMilliseconds, 0)

        XCTAssertEqual(
            try reader.readObservation().powerTelemetry.presence,
            .missing
        )
        let afterMissingTelemetry = try reader.readObservation()
            .powerTelemetry.freshness
        XCTAssertEqual(afterMissingTelemetry.assessment, .changed)
        XCTAssertEqual(afterMissingTelemetry.unchangedForMilliseconds, 0)

        XCTAssertEqual(
            try reader.readObservation().powerTelemetry.presence,
            .invalid
        )
        let afterInvalidTelemetry = try reader.readObservation()
            .powerTelemetry.freshness
        XCTAssertEqual(afterInvalidTelemetry.assessment, .changed)
        XCTAssertEqual(afterInvalidTelemetry.unchangedForMilliseconds, 0)
    }

    func testTelemetryFreezeTrackerDoesNotAutoDeclareStale() throws {
        var tracker = TelemetryFreezeTracker()
        _ = try tracker.observe(
            updateToken: "token-a",
            evaluatedAtContinuousNanoseconds: 0
        )
        let later = try tracker.observe(
            updateToken: "token-a",
            evaluatedAtContinuousNanoseconds: 120_000_000_000
        )

        XCTAssertEqual(later.assessment, .unchanged)
        XCTAssertNotEqual(later.assessment, .stale)
    }

    func testWriterCreatesPartialFileWith0600Permissions() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let writer = try makeWriter(directory: directory)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: writer.partialURLForTest.path
        ))
        XCTAssertEqual(fileMode(writer.partialURLForTest), 0o600)
    }

    func testDefaultOutputDirectoryIsCreatedWith0700Permissions() throws {
        let parent = temporaryDirectory()
        defer { remove(parent) }
        let directory = parent.appendingPathComponent("nested/captures")
        _ = try makeWriter(directory: directory)

        XCTAssertEqual(fileMode(directory), 0o700)
    }

    func testWriterProducesMutuallyExclusiveHeaderSampleFooterRecords() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let writer = try makeWriter(directory: directory)
        XCTAssertEqual(
            try writer.append(.canonicalFixture(sequence: 0)),
            .written
        )
        let final = try writer.finalize(
            termination: .completed,
            terminationSignal: nil,
            fatalErrorCode: nil
        )
        let objects = try jsonObjects(final)

        XCTAssertEqual(objects.count, 3)
        XCTAssertNotNil(objects[0]["header"] as? [String: Any])
        XCTAssertTrue(objects[0]["sample"] is NSNull)
        XCTAssertTrue(objects[0]["footer"] is NSNull)
        XCTAssertTrue(objects[1]["header"] is NSNull)
        XCTAssertNotNil(objects[1]["sample"] as? [String: Any])
        XCTAssertTrue(objects[1]["footer"] is NSNull)
        XCTAssertTrue(objects[2]["header"] is NSNull)
        XCTAssertTrue(objects[2]["sample"] is NSNull)
        XCTAssertNotNil(objects[2]["footer"] as? [String: Any])
    }

    func testWriterUsesNoReplaceAtomicFinalization() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let writer = try makeWriter(directory: directory)
        let partial = writer.partialURLForTest
        let final = try writer.finalize(
            termination: .completed,
            terminationSignal: nil,
            fatalErrorCode: nil
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))
    }

    func testWriterNeverOverwritesExistingFinalFile() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let writer = try makeWriter(directory: directory)
        let sentinel = Data("do-not-overwrite".utf8)
        try sentinel.write(to: writer.finalURLForTest)

        XCTAssertThrowsError(try writer.finalize(
            termination: .completed,
            terminationSignal: nil,
            fatalErrorCode: nil
        )) { error in
            XCTAssertEqual(error as? PowerObservationWriterError, .outputExists)
        }
        XCTAssertEqual(try Data(contentsOf: writer.finalURLForTest), sentinel)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: writer.partialURLForTest.path
        ))
    }

    func testWriterRejectsSymlinkOutputDirectory() throws {
        let parent = temporaryDirectory()
        defer { remove(parent) }
        let real = parent.appendingPathComponent("real")
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createDirectory(
            at: real,
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: real
        )

        XCTAssertThrowsError(try makeWriter(directory: link)) { error in
            XCTAssertEqual(
                error as? PowerObservationWriterError,
                .unsafeOutputDirectory
            )
        }
    }

    func testWriterStopsAtSixteenMiBAndWritesSizeLimitFooter() throws {
        XCTAssertEqual(
            PowerObservationJSONLWriter.defaultMaximumFileBytes,
            16 * 1024 * 1024
        )
        XCTAssertEqual(
            PowerObservationJSONLWriter.defaultMaximumDirectoryBytes,
            64 * 1024 * 1024
        )
        XCTAssertEqual(
            PowerObservationJSONLWriter.defaultCleanupTargetBytes,
            48 * 1024 * 1024
        )
        XCTAssertEqual(
            PowerObservationJSONLWriter.reservedFooterBytes,
            1024
        )
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let writer = try makeWriter(
            directory: directory,
            maximumFileBytes: 4_096,
            maximumDirectoryBytes: 16_384,
            cleanupTargetBytes: 8_192
        )
        let result = try writer.append(
            .canonicalFixture(sequence: 0)
        )

        XCTAssertEqual(result, .fileLimitReached)
        let final = try XCTUnwrap(writer.finalizedURL)
        let objects = try jsonObjects(final)
        let footer = try XCTUnwrap(objects.last?["footer"] as? [String: Any])
        XCTAssertEqual(footer["termination"] as? String, "sizeLimit")
        XCTAssertLessThanOrEqual(
            (try FileManager.default.attributesOfItem(
                atPath: final.path
            )[.size] as? NSNumber)?.intValue ?? .max,
            4_096
        )
    }

    func testWriterCleansOnlyEligibleCompleteFilesToDirectoryTarget() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        try writeBytes(700, to: directory.appendingPathComponent(
            "wattson-power-v1-old-1.jsonl"
        ))
        try writeBytes(700, to: directory.appendingPathComponent(
            "wattson-power-v1-old-2.recovered.jsonl"
        ))
        let partial = directory.appendingPathComponent(
            "wattson-power-v1-active-3.partial"
        )
        try writeBytes(100, to: partial)

        _ = try makeWriter(
            directory: directory,
            maximumFileBytes: 2_000,
            maximumDirectoryBytes: 5_000,
            cleanupTargetBytes: 900
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
        let complete = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).filter { $0.hasSuffix(".jsonl") }
        XCTAssertLessThanOrEqual(complete.count, 1)

        let preciseDirectory = temporaryDirectory()
        defer { remove(preciseDirectory) }
        let newer = preciseDirectory.appendingPathComponent(
            "wattson-power-v1-a-newer.jsonl"
        )
        let older = preciseDirectory.appendingPathComponent(
            "wattson-power-v1-z-older.jsonl"
        )
        try writeBytes(700, to: newer)
        try writeBytes(700, to: older)
        try setModificationTime(
            older,
            seconds: 1_700_000_000,
            nanoseconds: 100
        )
        try setModificationTime(
            newer,
            seconds: 1_700_000_000,
            nanoseconds: 900
        )

        _ = try makeWriter(
            directory: preciseDirectory,
            maximumFileBytes: 2_000,
            maximumDirectoryBytes: 5_000,
            cleanupTargetBytes: 900
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: older.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newer.path))

#if canImport(Darwin)
        let deletionFailureDirectory = temporaryDirectory()
        let undeletableOldest = deletionFailureDirectory
            .appendingPathComponent(
                "wattson-power-v1-undeletable-oldest.jsonl"
            )
        let newerEvidence = deletionFailureDirectory
            .appendingPathComponent(
                "wattson-power-v1-preserve-newer.jsonl"
            )
        try writeBytes(700, to: undeletableOldest)
        try writeBytes(700, to: newerEvidence)
        try setModificationTime(
            undeletableOldest,
            seconds: 1_700_000_001,
            nanoseconds: 100
        )
        try setModificationTime(
            newerEvidence,
            seconds: 1_700_000_001,
            nanoseconds: 900
        )
        XCTAssertEqual(
            chflags(undeletableOldest.path, UInt32(UF_IMMUTABLE)),
            0
        )
        defer {
            _ = chflags(undeletableOldest.path, 0)
            remove(deletionFailureDirectory)
        }

        XCTAssertThrowsError(try makeWriter(
            directory: deletionFailureDirectory,
            maximumFileBytes: 2_000,
            maximumDirectoryBytes: 5_000,
            cleanupTargetBytes: 900
        )) { error in
            XCTAssertEqual(
                error as? PowerObservationWriterError,
                .unsafeOutputDirectory
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: undeletableOldest.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: newerEvidence.path
        ))
#endif
    }

    func testWriterNeverDeletesPartialOrForeignFiles() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let partial = directory.appendingPathComponent(
            "wattson-power-v1-retain.partial"
        )
        let foreign = directory.appendingPathComponent("unrelated.bin")
        let eligible = directory.appendingPathComponent(
            "wattson-power-v1-delete.jsonl"
        )
        try writeBytes(100, to: partial)
        try writeBytes(100, to: foreign)
        try writeBytes(800, to: eligible)

        _ = try makeWriter(
            directory: directory,
            maximumFileBytes: 2_000,
            maximumDirectoryBytes: 5_000,
            cleanupTargetBytes: 300
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: eligible.path))

        let budgetDirectory = temporaryDirectory()
        defer { remove(budgetDirectory) }
        let retainedPartial = budgetDirectory.appendingPathComponent(
            "wattson-power-v1-budget.partial"
        )
        try writeBytes(1_000, to: retainedPartial)

        XCTAssertThrowsError(try makeWriter(
            directory: budgetDirectory,
            maximumFileBytes: 2_000,
            maximumDirectoryBytes: 2_500,
            cleanupTargetBytes: 1_500
        )) { error in
            XCTAssertEqual(
                error as? PowerObservationWriterError,
                .unsafeOutputDirectory
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: retainedPartial.path
        ))
    }

    func testPartialRecoveryKeepsOnlyNewlineTerminatedRecords() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let partial = directory.appendingPathComponent(
            "wattson-power-v1-recovery-1.partial"
        )
        try Data("{\"a\":1}\n{\"b\":2}\n{\"cut\":".utf8)
            .write(to: partial)
        let recovered = try withUmask(0o277) {
            try PowerObservationJSONLWriter
                .recoverEligiblePartials(in: directory)
        }
        let file = try XCTUnwrap(recovered.first)

        XCTAssertEqual(fileMode(file), 0o600)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: file), as: UTF8.self),
            "{\"a\":1}\n{\"b\":2}\n"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.path))

        let overBudgetDirectory = temporaryDirectory()
        defer { remove(overBudgetDirectory) }
        for index in 0..<3 {
            try writeSparseBytes(
                16 * 1024 * 1024,
                to: overBudgetDirectory.appendingPathComponent(
                    "wattson-power-v1-budget-\(index).partial"
                )
            )
        }
        try writeSparseBytes(
            1,
            to: overBudgetDirectory.appendingPathComponent(
                "wattson-power-v1-budget-3.partial"
            )
        )

        XCTAssertThrowsError(
            try PowerObservationJSONLWriter.recoverEligiblePartials(
                in: overBudgetDirectory
            )
        ) { error in
            XCTAssertEqual(
                error as? PowerObservationWriterError,
                .unsafeOutputDirectory
            )
        }
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: overBudgetDirectory.path
            ).allSatisfy { $0.hasSuffix(".partial") }
        )

        let interruptedRecoveryDirectory = temporaryDirectory()
        defer { remove(interruptedRecoveryDirectory) }
        let originalPartial = interruptedRecoveryDirectory
            .appendingPathComponent(
                "wattson-power-v1-interrupted-1.partial"
            )
        let staleRecoveryTemporary = interruptedRecoveryDirectory
            .appendingPathComponent(
                "wattson-power-v1-interrupted-1.recovered.partial"
            )
        try Data("{\"sample\":1}\n".utf8).write(
            to: originalPartial
        )
        try Data("bounded-temporary".utf8).write(
            to: staleRecoveryTemporary
        )

        XCTAssertThrowsError(
            try PowerObservationJSONLWriter.recoverEligiblePartials(
                in: interruptedRecoveryDirectory
            )
        ) { error in
            XCTAssertEqual(
                error as? PowerObservationWriterError,
                .outputExists
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: originalPartial.path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: staleRecoveryTemporary.path
        ))
    }

    func testPartialRecoveryDoesNotInventFooter() throws {
        let directory = temporaryDirectory()
        defer { remove(directory) }
        let partial = directory.appendingPathComponent(
            "wattson-power-v1-no-footer-1.partial"
        )
        try Data("{\"recordType\":\"sample\"}\ntruncated".utf8)
            .write(to: partial)
        let recovered = try PowerObservationJSONLWriter
            .recoverEligiblePartials(in: directory)
        let text = String(
            decoding: try Data(contentsOf: XCTUnwrap(recovered.first)),
            as: UTF8.self
        )

        XCTAssertFalse(text.contains("footer"))
        XCTAssertEqual(text, "{\"recordType\":\"sample\"}\n")
    }

    func testCaptureCommandRejectsMissingScenario() {
        let harness = CommandHarness()
        let code = PowerObservationCaptureCommand.run(
            arguments: ["--power-observation-capture"],
            dependencies: harness.dependencies
        )

        XCTAssertEqual(code, 64)
        XCTAssertFalse(harness.writerFactoryCalled)
    }

    func testCaptureCommandRejectsUnsafeScenarioLabel() {
        let harness = CommandHarness()
        let code = PowerObservationCaptureCommand.run(
            arguments: [
                "--power-observation-capture",
                "--scenario", "../../unsafe",
            ],
            dependencies: harness.dependencies
        )

        XCTAssertEqual(code, 64)
        XCTAssertFalse(harness.writerFactoryCalled)
    }

    func testCaptureCommandRejectsDurationAboveSixHundredSeconds() {
        let harness = CommandHarness()
        let code = PowerObservationCaptureCommand.run(
            arguments: [
                "--power-observation-capture",
                "--scenario", "duration",
                "--duration", "601",
            ],
            dependencies: harness.dependencies
        )

        XCTAssertEqual(code, 64)
        XCTAssertFalse(harness.writerFactoryCalled)
    }

    func testCaptureCommandRejectsIntervalBelowOneHundredMilliseconds() {
        let harness = CommandHarness()
        let code = PowerObservationCaptureCommand.run(
            arguments: [
                "--power-observation-capture",
                "--scenario", "interval",
                "--interval-ms", "99",
            ],
            dependencies: harness.dependencies
        )

        XCTAssertEqual(code, 64)
        XCTAssertFalse(harness.writerFactoryCalled)
    }

    func testCaptureCommandMapsSIGINTToInterruptedFooterAndExit130() {
        let writer = RecordingWriter()
        let harness = CommandHarness(
            writer: writer,
            signal: SequenceSignalState([nil, SIGINT])
        )
        let code = harness.runValidCommand()

        XCTAssertEqual(code, 130)
        XCTAssertEqual(writer.finalTermination, .interrupted)
        XCTAssertEqual(writer.finalSignal, SIGINT)
    }

    func testCaptureCommandMapsSIGTERMToInterruptedFooterAndExit143() {
        let writer = RecordingWriter()
        let harness = CommandHarness(
            writer: writer,
            signal: SequenceSignalState([nil, SIGTERM])
        )
        let code = harness.runValidCommand()

        XCTAssertEqual(code, 143)
        XCTAssertEqual(writer.finalTermination, .interrupted)
        XCTAssertEqual(writer.finalSignal, SIGTERM)
    }

    func testCaptureCommandWritesFatalErrorFooterAndExit70() {
        let writer = RecordingWriter()
        let harness = CommandHarness(
            writer: writer,
            collector: ThrowingCollector(
                error: PowerObservationCollectorError.smcReaderFailed
            )
        )
        let code = harness.runValidCommand()

        XCTAssertEqual(code, 70)
        XCTAssertEqual(writer.finalTermination, .fatalError)
        XCTAssertEqual(writer.finalErrorCode, "smc-reader-failed")

        let encodingWriter = RecordingWriter(
            appendError: PowerObservationEncodingError.failed
        )
        let encodingHarness = CommandHarness(writer: encodingWriter)
        XCTAssertEqual(encodingHarness.runValidCommand(), 70)
        XCTAssertEqual(encodingWriter.finalTermination, .fatalError)
        XCTAssertEqual(encodingWriter.finalErrorCode, "encoding-failed")
    }

    func testCaptureCommandLeavesPartialWhenFooterWriteFails() {
        let writer = RecordingWriter(finalizeError: .writeFailed)
        let harness = CommandHarness(
            writer: writer,
            collector: ThrowingCollector(
                error: PowerObservationCollectorError.invalidObservation
            )
        )
        let code = harness.runValidCommand()

        XCTAssertEqual(code, 74)
        XCTAssertTrue(writer.partialRemains)
        XCTAssertNil(writer.finalTermination)

        let collisionWriter = RecordingWriter(
            finalizeError: .outputExists
        )
        let collisionHarness = CommandHarness(
            writer: collisionWriter,
            collector: ThrowingCollector(
                error: PowerObservationCollectorError.invalidObservation
            )
        )
        XCTAssertEqual(collisionHarness.runValidCommand(), 73)
        XCTAssertTrue(collisionWriter.partialRemains)

        let headerWriteHarness = CommandHarness(
            writerFactoryError: PowerObservationWriterError.writeFailed
        )
        XCTAssertEqual(headerWriteHarness.runValidCommand(), 74)

        let recoveryWriteHarness = CommandHarness(
            recoveryError: PowerObservationWriterError.writeFailed
        )
        XCTAssertEqual(recoveryWriteHarness.runValidCommand(), 74)

        let recoverySyncHarness = CommandHarness(
            recoveryError: PowerObservationWriterError.syncFailed
        )
        XCTAssertEqual(recoverySyncHarness.runValidCommand(), 74)

        let recoverySafetyHarness = CommandHarness(
            recoveryError:
                PowerObservationWriterError.unsafeOutputDirectory
        )
        XCTAssertEqual(recoverySafetyHarness.runValidCommand(), 73)
    }
}

// MARK: - Test support

private func interval(_ start: UInt64, _ end: UInt64) throws -> MonotonicInterval {
    try MonotonicInterval(
        startedContinuousNanoseconds: start,
        endedContinuousNanoseconds: end
    )
}

private func smcKey(
    _ key: String,
    _ source: ObservationSource,
    _ watts: Double,
    _ capture: MonotonicInterval
) -> SMCKeyObservation {
    SMCKeyObservation(
        key: key,
        source: source,
        status: .present,
        capture: capture,
        dataTypeFourCC: "flt ",
        rawBytesHex: "00000000",
        decodedWatts: watts,
        ioReturn: nil,
        validationIssue: nil
    )
}

private func presentSMCResult(_ watts: Double) -> DirectSMCRawKeyResult {
    DirectSMCRawKeyResult(
        status: .present,
        dataTypeFourCC: "flt ",
        rawBytes: [0, 0, 0, 0],
        decodedWatts: watts,
        ioReturn: nil,
        validationIssue: nil
    )
}

private func littleEndianFloatBytes(_ value: Float) -> [UInt8] {
    let bits = value.bitPattern
    return [
        UInt8(bits & 0xFF),
        UInt8((bits >> 8) & 0xFF),
        UInt8((bits >> 16) & 0xFF),
        UInt8((bits >> 24) & 0xFF),
    ]
}

private final class RecordingSMCConnection: DirectSMCConnectionReading {
    private let results: [String: DirectSMCRawKeyResult]
    private let lock = NSLock()
    private(set) var requestedKeys: [String] = []
    private(set) var closeCount = 0

    init(results: [String: DirectSMCRawKeyResult]) {
        self.results = results
    }

    func readKey(_ key: String) -> DirectSMCRawKeyResult {
        lock.lock()
        requestedKeys.append(key)
        lock.unlock()
        return results[key] ?? .unavailable(issue: "missing fixture result")
    }

    func close() {
        lock.lock()
        closeCount += 1
        lock.unlock()
    }
}

private final class RecordingSMCOpener: DirectSMCConnectionOpening {
    let connection: RecordingSMCConnection
    private(set) var openCount = 0

    init(connection: RecordingSMCConnection) {
        self.connection = connection
    }

    func openConnection() -> DirectSMCConnectionOpenResult {
        openCount += 1
        return .opened(connection)
    }
}

private final class IncrementingClock: ContinuousNanosecondClockReading {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func nowContinuousNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let result = value
        value += 1_000_000
        return result
    }
}

private final class SequenceClock: ContinuousNanosecondClockReading {
    private let lock = NSLock()
    private var values: [UInt64]
    private var last: UInt64

    init(_ values: [UInt64]) {
        self.values = values
        last = values.last ?? 0
    }

    func nowContinuousNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return last }
        last = values.removeFirst()
        return last
    }
}

private struct SyntheticBatterySnapshotReader:
    AppleSmartBatteryRawSnapshotReading
{
    let snapshot: AppleSmartBatteryRawSnapshot

    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryRawSnapshot {
        let allowed = Set(keys)
        return AppleSmartBatteryRawSnapshot(
            servicePresent: snapshot.servicePresent,
            properties: snapshot.properties.filter {
                allowed.contains($0.key)
            }
        )
    }
}

private final class SequenceBatterySnapshotReader:
    AppleSmartBatteryRawSnapshotReading
{
    private let lock = NSLock()
    private var snapshots: [AppleSmartBatteryRawSnapshot]

    init(_ snapshots: [AppleSmartBatteryRawSnapshot]) {
        self.snapshots = snapshots
    }

    func readAllowlistedProperties(
        _ keys: [String]
    ) -> AppleSmartBatteryRawSnapshot {
        lock.lock()
        defer { lock.unlock() }
        precondition(!snapshots.isEmpty)
        let snapshot = snapshots.removeFirst()
        let allowed = Set(keys)
        return AppleSmartBatteryRawSnapshot(
            servicePresent: snapshot.servicePresent,
            properties: snapshot.properties.filter {
                allowed.contains($0.key)
            }
        )
    }
}

private struct FixedBatteryReader: AppleSmartBatteryObservationReading {
    let value: AppleSmartBatteryObservation
    func readObservation() throws -> AppleSmartBatteryObservation { value }
}

private struct FixedSMCReader: DirectSMCObservationReading {
    let value: SMCObservation
    func readObservation() throws -> SMCObservation { value }
}

private final class BlockingBatteryReader: AppleSmartBatteryObservationReading {
    let started: DispatchSemaphore
    let release: DispatchSemaphore
    let value: AppleSmartBatteryObservation

    init(
        started: DispatchSemaphore,
        release: DispatchSemaphore,
        value: AppleSmartBatteryObservation
    ) {
        self.started = started
        self.release = release
        self.value = value
    }

    func readObservation() throws -> AppleSmartBatteryObservation {
        started.signal()
        _ = release.wait(timeout: .now() + 1)
        return value
    }
}

private final class BlockingSMCReader: DirectSMCObservationReading {
    let started: DispatchSemaphore
    let release: DispatchSemaphore
    let value: SMCObservation

    init(
        started: DispatchSemaphore,
        release: DispatchSemaphore,
        value: SMCObservation
    ) {
        self.started = started
        self.release = release
        self.value = value
    }

    func readObservation() throws -> SMCObservation {
        started.signal()
        _ = release.wait(timeout: .now() + 1)
        return value
    }
}

private final class LockedResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        value = result
        lock.unlock()
    }

    func load() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try! FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return directory
}

private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func fileMode(_ url: URL) -> Int {
    var status = stat()
    guard lstat(url.path, &status) == 0 else { return -1 }
    return Int(status.st_mode & 0o777)
}

private func makeHeader() -> PowerObservationTraceHeader {
    PowerObservationTraceHeader(
        captureTool: "Tests",
        captureToolVersion: 1,
        scenario: "writer-test",
        requestedIntervalMilliseconds: 250,
        requestedDurationSeconds: 1,
        startedContinuousNanoseconds: 1,
        macModel: "FixtureMac",
        architecture: "arm64",
        operatingSystemVersion: "26.5.2",
        operatingSystemBuild: "25F84"
    )
}

private func makeWriter(
    directory: URL,
    maximumFileBytes: Int = 16 * 1024 * 1024,
    maximumDirectoryBytes: Int = 64 * 1024 * 1024,
    cleanupTargetBytes: Int = 48 * 1024 * 1024
) throws -> PowerObservationJSONLWriter {
    try PowerObservationJSONLWriter(
        outputDirectory: directory,
        header: makeHeader(),
        maximumFileBytes: maximumFileBytes,
        maximumDirectoryBytes: maximumDirectoryBytes,
        cleanupTargetBytes: cleanupTargetBytes
    )
}

private func jsonObjects(_ url: URL) throws -> [[String: Any]] {
    try Data(contentsOf: url).split(separator: 0x0A).map { line in
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line))
                as? [String: Any]
        )
    }
}

private func writeBytes(_ count: Int, to url: URL) throws {
    try Data(repeating: 0x41, count: count).write(to: url)
}

private func writeSparseBytes(_ count: Int, to url: URL) throws {
    let fileDescriptor = open(
        url.path,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
        mode_t(0o600)
    )
    guard fileDescriptor >= 0 else {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno)
        )
    }
    defer { close(fileDescriptor) }
    guard ftruncate(fileDescriptor, off_t(count)) == 0 else {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno)
        )
    }
}

private func withUmask<Value>(
    _ mask: mode_t,
    _ body: () throws -> Value
) rethrows -> Value {
    let previous = umask(mask)
    defer { _ = umask(previous) }
    return try body()
}

private func setModificationTime(
    _ url: URL,
    seconds: Int,
    nanoseconds: Int
) throws {
    var times = [
        timespec(tv_sec: seconds, tv_nsec: nanoseconds),
        timespec(tv_sec: seconds, tv_nsec: nanoseconds),
    ]
    let result = url.path.withCString { path in
        times.withUnsafeMutableBufferPointer { buffer in
            utimensat(AT_FDCWD, path, buffer.baseAddress, 0)
        }
    }
    guard result == 0 else {
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno)
        )
    }
}

private func sortedEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
}

private final class RecordingWriter: PowerObservationWriting {
    let appendError: Error?
    let finalizeError: PowerObservationWriterError?
    private(set) var appendCount = 0
    private(set) var finalTermination: TraceTermination?
    private(set) var finalSignal: Int32?
    private(set) var finalErrorCode: String?
    private(set) var partialRemains = true

    init(
        appendError: Error? = nil,
        finalizeError: PowerObservationWriterError? = nil
    ) {
        self.appendError = appendError
        self.finalizeError = finalizeError
    }

    func append(
        _ observation: RawPowerObservation
    ) throws -> PowerObservationAppendResult {
        if let appendError { throw appendError }
        appendCount += 1
        return .written
    }

    func finalize(
        termination: TraceTermination,
        terminationSignal: Int32?,
        fatalErrorCode: String?
    ) throws -> URL {
        if let finalizeError { throw finalizeError }
        finalTermination = termination
        finalSignal = terminationSignal
        finalErrorCode = fatalErrorCode
        partialRemains = false
        return URL(fileURLWithPath: "/tmp/fake.jsonl")
    }
}

private struct FixedCollector: RawPowerObservationCollecting {
    func collect(
        sequence: UInt64,
        scenario: String?
    ) throws -> RawPowerObservation {
        .canonicalFixture(sequence: sequence, scenario: scenario)
    }
}

private struct ThrowingCollector: RawPowerObservationCollecting {
    let error: Error
    func collect(
        sequence: UInt64,
        scenario: String?
    ) throws -> RawPowerObservation {
        throw error
    }
}

private final class SequenceSignalState: PowerObservationSignalReading {
    private let lock = NSLock()
    private var values: [Int32?]

    init(_ values: [Int32?]) { self.values = values }

    func pendingSignal() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

private struct NoopSleeper: PowerObservationSleeping {
    func sleep(nanoseconds: UInt64) {}
}

private final class CommandHarness {
    let writer: RecordingWriter
    let collector: any RawPowerObservationCollecting
    let signal: any PowerObservationSignalReading
    let writerFactoryError: Error?
    let recoveryError: Error?
    private(set) var writerFactoryCalled = false

    init(
        writer: RecordingWriter = RecordingWriter(),
        signal: any PowerObservationSignalReading =
            SequenceSignalState([nil, nil]),
        collector: any RawPowerObservationCollecting = FixedCollector(),
        writerFactoryError: Error? = nil,
        recoveryError: Error? = nil
    ) {
        self.writer = writer
        self.signal = signal
        self.collector = collector
        self.writerFactoryError = writerFactoryError
        self.recoveryError = recoveryError
    }

    var dependencies: PowerObservationCaptureCommandDependencies {
        PowerObservationCaptureCommandDependencies(
            clock: SequenceClock([0, 0, 0, 0]),
            collector: collector,
            sleeper: NoopSleeper(),
            signalState: signal,
            environment: PowerObservationCaptureEnvironment(
                macModel: "FixtureMac",
                architecture: "arm64",
                operatingSystemVersion: "26.5.2",
                operatingSystemBuild: "25F84"
            ),
            writerFactory: { [weak self] _, _ in
                self?.writerFactoryCalled = true
                if let error = self?.writerFactoryError {
                    throw error
                }
                return self!.writer
            },
            recoverPartials: { [weak self] _ in
                if let error = self?.recoveryError {
                    throw error
                }
                return []
            }
        )
    }

    func runValidCommand() -> Int32 {
        PowerObservationCaptureCommand.run(
            arguments: [
                "--power-observation-capture",
                "--scenario", "command-test",
                "--duration", "1",
                "--interval-ms", "250",
                "--output-dir", temporaryDirectory().path,
            ],
            dependencies: dependencies
        )
    }
}
