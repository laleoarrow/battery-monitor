import XCTest
@testable import WattsonHelperV5Support

final class PowerObservationV5SupportTests: XCTestCase {
    final class FakeBackend: HelperV5SMCBackend {
        var events: [String] = []
        var openResult = HelperV5ConnectionOpenResult(
            status: .opened,
            ioReturn: nil,
            validationIssue: nil
        )
        var results: [HelperV5FixedSMCKey: HelperV5RawKeyResult] = [:]

        func open() -> HelperV5ConnectionOpenResult {
            events.append("open")
            return openResult
        }

        func read(_ key: HelperV5FixedSMCKey) -> HelperV5RawKeyResult {
            events.append(key.rawValue)
            return results[key] ?? .present(watts: Double(events.count))
        }

        func close() { events.append("close") }
    }

    struct FakeClock: HelperV5ContinuousClock {
        final class State: @unchecked Sendable {
            var values: [UInt64]
            init(_ values: [UInt64]) { self.values = values }
        }
        let state: State
        init(_ values: [UInt64]) { state = State(values) }
        func nowContinuousNanoseconds() -> UInt64 {
            state.values.isEmpty ? 0 : state.values.removeFirst()
        }
    }

    func testStrictRequestDecoderAcceptsOnlyExactV5OperationAndUInt64Sequence() throws {
        let valid = try JSONSerialization.data(withJSONObject: [
            "_wattsonProtocol": 5,
            "op": "getPowerObservation",
            "clientSequence": NSNumber(value: UInt64.max),
        ], options: [.sortedKeys])
        XCTAssertEqual(
            HelperV5RequestDecoder().decode(frame: valid),
            .request(HelperV5RequestPayload(clientSequence: UInt64.max))
        )

        let old = try JSONSerialization.data(withJSONObject: [
            "_wattsonProtocol": 4,
            "op": "getPower",
        ])
        XCTAssertEqual(HelperV5RequestDecoder().decode(frame: old), .notV5)

        let malformedProtocol = try JSONSerialization.data(withJSONObject: [
            "_wattsonProtocol": "5",
            "op": "getPowerObservation",
            "clientSequence": 1,
        ])
        XCTAssertEqual(
            HelperV5RequestDecoder().decode(frame: malformedProtocol),
            .malformed
        )

        let unknownField = try JSONSerialization.data(withJSONObject: [
            "_wattsonProtocol": 5,
            "op": "getPowerObservation",
            "clientSequence": 1,
            "key": "PDTR",
        ])
        XCTAssertEqual(
            HelperV5RequestDecoder().decode(frame: unknownField),
            .malformed
        )
    }

    func testRequestServiceEchoesSequenceAndReturnsNewlineFramedResponse() throws {
        let service = HelperV5PowerObservationService(
            reader: HelperPowerObservationV5Reader(
                backend: FakeBackend(),
                clock: FakeClock([1,2,3,4,5,6,7,8])
            )
        )
        let request = try JSONSerialization.data(withJSONObject: [
            "_wattsonProtocol": 5,
            "op": "getPowerObservation",
            "clientSequence": 42,
        ], options: [.sortedKeys])
        guard case let .response(line) = service.handle(frame: request) else {
            return XCTFail("valid v5 request must produce a response")
        }
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        let payload = try JSONDecoder().decode(
            HelperV5ResponsePayload.self,
            from: line.dropLast()
        )
        XCTAssertEqual(payload.clientSequence, 42)
        XCTAssertEqual(payload.keys.map(\.key), ["PDTR", "PSTR", "PPBR"])
    }

    func testReaderUsesOneConnectionAndFixedPDTRPSTRPPBROrder() {
        let backend = FakeBackend()
        let reader = HelperPowerObservationV5Reader(
            backend: backend,
            clock: FakeClock([1, 2, 3, 4, 5, 6, 7, 8])
        )
        let response = reader.read(clientSequence: 9)
        XCTAssertEqual(backend.events, ["open", "PDTR", "PSTR", "PPBR", "close"])
        XCTAssertEqual(response.keys.map(\.key), ["PDTR", "PSTR", "PPBR"])
        XCTAssertTrue(response.ok)
        XCTAssertFalse(response.partial)
    }

    func testSingleKeyFailureDoesNotPreventLaterKeys() {
        let backend = FakeBackend()
        backend.results[.PSTR] = HelperV5RawKeyResult(
            status: .keyInfoFailed,
            dataTypeFourCC: nil,
            rawBytes: nil,
            decodedWatts: nil,
            ioReturn: -1,
            validationIssue: "fixture failure"
        )
        let response = HelperPowerObservationV5Reader(
            backend: backend,
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 1)
        XCTAssertEqual(backend.events, ["open", "PDTR", "PSTR", "PPBR", "close"])
        XCTAssertEqual(response.keys[1].status, .keyInfoFailed)
        XCTAssertEqual(response.keys[1].validationIssue, "key info failed")
        XCTAssertEqual(response.keys[2].status, .present)
        XCTAssertTrue(response.ok)
        XCTAssertTrue(response.partial)

        let connectionLostBackend = FakeBackend()
        connectionLostBackend.results[.PSTR] = HelperV5RawKeyResult(
            status: .connectionUnavailable,
            dataTypeFourCC: nil,
            rawBytes: nil,
            decodedWatts: nil,
            ioReturn: -1,
            validationIssue: "backend connection detail"
        )
        let connectionLostResponse = HelperPowerObservationV5Reader(
            backend: connectionLostBackend,
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 2)
        XCTAssertEqual(connectionLostResponse.keys[1].status, .keyInfoFailed)
        XCTAssertEqual(
            connectionLostResponse.keys[1].validationIssue,
            "key info failed"
        )
        XCTAssertNotNil(connectionLostResponse.encodedLine())
    }

    func testConnectionFailureReturnsThreeExplicitUnavailableKeys() {
        let backend = FakeBackend()
        backend.openResult = HelperV5ConnectionOpenResult(
            status: .openFailed,
            ioReturn: 5,
            validationIssue: "backend detail must not cross the boundary"
        )
        let response = HelperPowerObservationV5Reader(
            backend: backend,
            clock: FakeClock([10, 11])
        ).read(clientSequence: 3)
        XCTAssertEqual(backend.events, ["open", "close"])
        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.partial)
        XCTAssertEqual(response.keys.map(\.status), [
            .connectionUnavailable, .connectionUnavailable, .connectionUnavailable,
        ])
        XCTAssertEqual(response.error, "open failed")
        XCTAssertEqual(response.connection.validationIssue, "open failed")
        XCTAssertTrue(response.keys.allSatisfy {
            $0.validationIssue == "connection unavailable"
        })
    }

    func testReaderEchoesClientSequenceAndMonotonicClockName() {
        let response = HelperPowerObservationV5Reader(
            backend: FakeBackend(),
            clock: FakeClock([100,101,102,103,104,105,106,107])
        ).read(clientSequence: UInt64.max)
        XCTAssertEqual(response.clientSequence, UInt64.max)
        XCTAssertEqual(response.clock, "CLOCK_MONOTONIC_RAW")
        XCTAssertEqual(response.wattsonProtocol, 5)
    }

    func testEncodedLineContainsRequiredNullableKeysAsNull() throws {
        let response = HelperPowerObservationV5Reader(
            backend: FakeBackend(),
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 1)
        let line = try XCTUnwrap(response.encodedLine())
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertLessThanOrEqual(
            line.count,
            HelperV5ResponsePayload.maximumResponseBytes
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any]
        )
        XCTAssertTrue(object.keys.contains("error"))
        XCTAssertTrue(object["error"] is NSNull)
        let connection = try XCTUnwrap(object["connection"] as? [String: Any])
        XCTAssertTrue(connection["ioReturn"] is NSNull)
        XCTAssertTrue(connection["validationIssue"] is NSNull)
        let keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        XCTAssertTrue(keys.allSatisfy { $0.keys.contains("validationIssue") })

        let oversizedKeys = response.keys.enumerated().map { index, key in
            HelperV5KeyPayload(
                key: key.key,
                source: key.source,
                status: key.status,
                startedNs: key.startedNs,
                endedNs: key.endedNs,
                dataType: key.dataType,
                rawBytesHex: index == 0
                    ? String(repeating: "AA", count: 2_048)
                    : key.rawBytesHex,
                watts: key.watts,
                ioReturn: key.ioReturn,
                validationIssue: key.validationIssue
            )
        }
        let oversized = HelperV5ResponsePayload(
            ok: response.ok,
            partial: response.partial,
            clientSequence: response.clientSequence,
            error: response.error,
            connection: response.connection,
            keys: oversizedKeys
        )
        XCTAssertNil(oversized.encodedLine())
        XCTAssertThrowsError(try JSONEncoder().encode(oversized))

        let invalidProtocol = HelperV5ResponsePayload(
            wattsonProtocol: 6,
            ok: response.ok,
            partial: response.partial,
            clientSequence: response.clientSequence,
            error: response.error,
            connection: response.connection,
            keys: response.keys
        )
        XCTAssertNil(invalidProtocol.encodedLine())
        XCTAssertThrowsError(try JSONEncoder().encode(invalidProtocol))
        var invalidProtocolObject = object
        invalidProtocolObject["_wattsonProtocol"] = 6
        let invalidProtocolData = try JSONSerialization.data(
            withJSONObject: invalidProtocolObject,
            options: [.sortedKeys]
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                HelperV5ResponsePayload.self,
                from: invalidProtocolData
            )
        )

        let invalidPartial = HelperV5ResponsePayload(
            ok: response.ok,
            partial: !response.partial,
            clientSequence: response.clientSequence,
            error: response.error,
            connection: response.connection,
            keys: response.keys
        )
        XCTAssertNil(invalidPartial.encodedLine())
    }

    func testReaderPreservesFinitePDTRAndPSTRWithoutRangeClampButRejectsNegativePPBR() {
        let backend = FakeBackend()
        backend.results[.PDTR] = .present(watts: 1_500.25)
        backend.results[.PSTR] = .present(watts: -2.5)
        backend.results[.PPBR] = .present(watts: -0.1)
        let response = HelperPowerObservationV5Reader(
            backend: backend,
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 1)
        XCTAssertEqual(response.keys[0].watts, 1_500.25)
        XCTAssertEqual(response.keys[1].watts, -2.5)
        XCTAssertEqual(response.keys[2].status, .invalidValue)
        XCTAssertNil(response.keys[2].watts)
        XCTAssertTrue(response.partial)
    }

    func testKeyUnavailableCanPreserveKnownTypeWithoutRawBytes() {
        let backend = FakeBackend()
        backend.results[.PSTR] = HelperV5RawKeyResult(
            status: .keyUnavailable,
            dataTypeFourCC: "flt ",
            rawBytes: nil,
            decodedWatts: nil,
            ioReturn: nil,
            validationIssue: "invalid key size"
        )
        let response = HelperPowerObservationV5Reader(
            backend: backend,
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 1)
        XCTAssertEqual(response.keys[1].status, .keyUnavailable)
        XCTAssertEqual(response.keys[1].dataType, "flt ")
        XCTAssertNil(response.keys[1].rawBytesHex)
        XCTAssertNil(response.keys[1].watts)
    }

    func testUnsupportedTypePreservesRawBytesAndDoesNotPublishWatts() {
        let backend = FakeBackend()
        backend.results[.PSTR] = HelperV5RawKeyResult(
            status: .unsupportedType,
            dataTypeFourCC: "ui16",
            rawBytes: [0x12, 0x34],
            decodedWatts: nil,
            ioReturn: nil,
            validationIssue: "unsupported"
        )
        let response = HelperPowerObservationV5Reader(
            backend: backend,
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 1)
        XCTAssertEqual(response.keys[1].dataType, "ui16")
        XCTAssertEqual(response.keys[1].rawBytesHex, "1234")
        XCTAssertNil(response.keys[1].watts)
    }

    func testResponseNeverSelectsPSTRBandOrComputesFusion() throws {
        let response = HelperPowerObservationV5Reader(
            backend: FakeBackend(),
            clock: FakeClock([1,2,3,4,5,6,7,8])
        ).read(clientSequence: 1)
        let text = String(decoding: try XCTUnwrap(response.encodedLine()), as: UTF8.self)
        for forbidden in ["selectedMultiple", "correctedPSTR", "unwrappedPSTR", "batteryW", "systemW", "adapterW"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testFixedKeyEnumExposesNoCallerSelectedSMCKey() {
        XCTAssertEqual(HelperV5FixedSMCKey.allCases.map(\.rawValue), ["PDTR", "PSTR", "PPBR"])
    }
}

private extension HelperV5RawKeyResult {
    static func present(watts: Double) -> Self {
        Self(
            status: .present,
            dataTypeFourCC: "flt ",
            rawBytes: [0, 0, 0, 0],
            decodedWatts: watts,
            ioReturn: nil,
            validationIssue: nil
        )
    }
}
