import Darwin
import Foundation
import XCTest
@testable import Wattson

final class PowerObservationWireV5Tests: XCTestCase {
    final class FakeTransport: @unchecked Sendable, PowerObservationFrameTransport {
        private let lock = NSLock()
        private var responses: [PowerObservationFrameExchange]
        private(set) var requests: [Data] = []
        private(set) var maximums: [Int] = []

        init(_ responses: [PowerObservationFrameExchange]) {
            self.responses = responses
        }

        func exchange(
            request: Data,
            maximumResponseBytes: Int,
            timeoutSeconds: Int
        ) -> PowerObservationFrameExchange {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            maximums.append(maximumResponseBytes)
            return responses.isEmpty ? .noResponse : responses.removeFirst()
        }
    }

    final class RealUnixSocketServer: @unchecked Sendable {
        private let socketPath: String
        private let listener: Int32
        private let responses: [Data]
        private let completion = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var recordedRequests: [Data] = []

        init(responses: [Data]) throws {
            self.responses = responses
            socketPath = "/tmp/wattson-wire-v5-\(UUID().uuidString).sock"
            listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard listener >= 0 else { throw POSIXError(.ENFILE) }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8)
            guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                Darwin.close(listener)
                throw POSIXError(.ENAMETOOLONG)
            }
            withUnsafeMutableBytes(of: &address.sun_path) { raw in
                raw.copyBytes(from: pathBytes)
            }
            let addressSize = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, addressSize)
                }
            }
            guard bound == 0, Darwin.listen(listener, 4) == 0 else {
                let failure = POSIXErrorCode(rawValue: errno) ?? .EIO
                Darwin.close(listener)
                Darwin.unlink(socketPath)
                throw POSIXError(failure)
            }
        }

        var path: String { socketPath }

        var requests: [Data] {
            lock.lock()
            defer { lock.unlock() }
            return recordedRequests
        }

        func start() {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer {
                    Darwin.close(listener)
                    Darwin.unlink(socketPath)
                    completion.signal()
                }

                for (index, response) in responses.enumerated() {
                    if index > 0 {
                        var descriptor = pollfd(
                            fd: listener,
                            events: Int16(POLLIN),
                            revents: 0
                        )
                        guard Darwin.poll(&descriptor, 1, 750) > 0 else { return }
                    }
                    guard let fd = acceptConnection() else { return }
                    record(readLine(from: fd))
                    _ = writeAll(response, to: fd)
                    Darwin.close(fd)
                }
            }
        }

        func waitForCompletion() -> Bool {
            completion.wait(timeout: .now() + 4) == .success
        }

        private func acceptConnection() -> Int32? {
            while true {
                let fd = Darwin.accept(listener, nil, nil)
                if fd >= 0 {
                    var noSigPipe: Int32 = 1
                    _ = setsockopt(
                        fd,
                        SOL_SOCKET,
                        SO_NOSIGPIPE,
                        &noSigPipe,
                        socklen_t(MemoryLayout<Int32>.size)
                    )
                    return fd
                }
                if errno != EINTR { return nil }
            }
        }

        private func readLine(from fd: Int32) -> Data {
            var data = Data()
            var byte: UInt8 = 0
            while data.count < 8_192 {
                let count = Darwin.recv(fd, &byte, 1, 0)
                if count == 1 {
                    data.append(byte)
                    if byte == UInt8(ascii: "\n") { break }
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            return data
        }

        private func record(_ request: Data) {
            lock.lock()
            recordedRequests.append(request)
            lock.unlock()
        }

        private func writeAll(_ data: Data, to fd: Int32) -> Bool {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return data.isEmpty }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(
                        fd,
                        base.advanced(by: offset),
                        raw.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if count < 0, errno == EINTR {
                        continue
                    } else {
                        return false
                    }
                }
                return true
            }
        }
    }

    func testV5RequestCarriesFixedProtocolOperationAndSequence() throws {
        let data = try JSONEncoder().encode(PowerObservationV5Request(clientSequence: 42))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["_wattsonProtocol"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual(object["op"] as? String, "getPowerObservation")
        XCTAssertEqual((object["clientSequence"] as? NSNumber)?.uint64Value, 42)
    }

    func testStrictDecoderPreservesThreeRawKeysAndTiming() throws {
        let response = validResponse(sequence: 7)
        let frame = try encoded(response)
        let outcome = PowerObservationV5Decoder().decode(frame: frame, expectedClientSequence: 7)
        guard case let .response(decoded) = outcome else {
            return XCTFail("expected valid response, got \(outcome)")
        }
        XCTAssertEqual(decoded.keys.map(\.key), ["PDTR", "PSTR", "PPBR"])
        XCTAssertEqual(decoded.key("PDTR")?.rawBytesHex, "00001842")
        XCTAssertEqual(decoded.key("PSTR")?.dataTypeFourCC, "flt ")
        XCTAssertEqual(decoded.connection.startedContinuousNanoseconds, 100)
        XCTAssertEqual(decoded.connection.endedContinuousNanoseconds, 140)
    }

    func testStrictDecoderRejectsMissingRequiredNullableKey() throws {
        var object = try responseObject(validResponse(sequence: 1))
        var connection = try XCTUnwrap(object["connection"] as? [String: Any])
        connection.removeValue(forKey: "validationIssue")
        object["connection"] = connection
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: object),
                expectedClientSequence: 1
            ),
            .malformed(.invalidConnection)
        )
    }

    func testStrictDecoderRejectsUnknownTopLevelField() throws {
        var object = try responseObject(validResponse(sequence: 1))
        object["future"] = 1
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: object),
                expectedClientSequence: 1
            ),
            .malformed(.unknownTopLevelField)
        )
    }

    func testInvalidProtocolFieldIsMalformedAndNeverFallsBack() throws {
        var object = try responseObject(validResponse(sequence: 1))
        object["_wattsonProtocol"] = "5"
        let frame = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: frame,
                expectedClientSequence: 1
            ),
            .malformed(.invalidProtocol)
        )
        let transport = FakeTransport([
            .frame(frame),
            .frame(legacyFrame(adapter: 1, system: 1)),
        ])
        XCTAssertEqual(
            PowerObservationV5Client(transport: transport).fetch(clientSequence: 1),
            .failed(.invalidV5(.invalidProtocol))
        )
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testStrictDecoderRejectsWrongSequence() throws {
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try encoded(validResponse(sequence: 9)),
                expectedClientSequence: 10
            ),
            .malformed(.sequenceMismatch)
        )
    }

    func testStrictDecoderRejectsReorderedOrMissingFixedKeys() throws {
        var object = try responseObject(validResponse(sequence: 1))
        var keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        keys.swapAt(0, 1)
        object["keys"] = keys
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: object),
                expectedClientSequence: 1
            ),
            .malformed(.invalidKeys)
        )
    }

    func testStrictDecoderRejectsPartialBitThatDisagreesWithKeyStatuses() throws {
        var object = try responseObject(validResponse(sequence: 1))
        object["partial"] = true
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: object),
                expectedClientSequence: 1
            ),
            .malformed(.semanticMismatch)
        )
    }

    func testStrictDecoderRejectsConnectionAndKeyStatusContradictions() throws {
        var failed = try responseObject(failedResponse(sequence: 1))
        var failedKeys = try XCTUnwrap(failed["keys"] as? [[String: Any]])
        failedKeys[0] = try XCTUnwrap(
            try responseObject(validResponse(sequence: 1))["keys"] as? [[String: Any]]
        )[0]
        failed["keys"] = failedKeys
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: failed),
                expectedClientSequence: 1
            ),
            .malformed(.invalidKey)
        )

        var opened = try responseObject(validResponse(sequence: 1))
        var openedKeys = try XCTUnwrap(opened["keys"] as? [[String: Any]])
        openedKeys[0]["status"] = "connectionUnavailable"
        openedKeys[0]["dataType"] = NSNull()
        openedKeys[0]["rawBytesHex"] = NSNull()
        openedKeys[0]["watts"] = NSNull()
        openedKeys[0]["validationIssue"] = "fixture unavailable"
        opened["keys"] = openedKeys
        opened["partial"] = true
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: opened),
                expectedClientSequence: 1
            ),
            .malformed(.invalidKey)
        )
    }

    func testStrictDecoderPreservesFinitePDTRAndPSTRWithoutUncontractedRangeClamp() throws {
        var object = try responseObject(validResponse(sequence: 1))
        var keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        keys[0]["watts"] = 1_500.25
        keys[1]["watts"] = -2.5
        object["keys"] = keys
        guard case let .response(response) = PowerObservationV5Decoder().decode(
            frame: try JSONSerialization.data(withJSONObject: object),
            expectedClientSequence: 1
        ) else { return XCTFail("finite raw PDTR/PSTR values must remain observable") }
        XCTAssertEqual(response.key("PDTR")?.decodedWatts, 1_500.25)
        XCTAssertEqual(response.key("PSTR")?.decodedWatts, -2.5)
    }

    func testStrictDecoderRejectsNegativePPBRMagnitude() throws {
        var object = try responseObject(validResponse(sequence: 1))
        var keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        keys[2]["watts"] = -0.1
        object["keys"] = keys
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: object),
                expectedClientSequence: 1
            ),
            .malformed(.invalidKey)
        )
    }

    func testStrictDecoderAllowsKeyUnavailableToPreserveKnownTypeMetadata() throws {
        var object = try responseObject(validResponse(sequence: 1))
        var keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        keys[1]["status"] = "keyUnavailable"
        keys[1]["dataType"] = "flt "
        keys[1]["rawBytesHex"] = NSNull()
        keys[1]["watts"] = NSNull()
        keys[1]["validationIssue"] = "invalid key size"
        object["keys"] = keys
        object["partial"] = true
        guard case let .response(response) = PowerObservationV5Decoder().decode(
            frame: try JSONSerialization.data(withJSONObject: object),
            expectedClientSequence: 1
        ) else { return XCTFail("known type metadata should be preserved") }
        XCTAssertEqual(response.key("PSTR")?.dataTypeFourCC, "flt ")
        XCTAssertNil(response.key("PSTR")?.rawBytesHex)
        XCTAssertNil(response.key("PSTR")?.decodedWatts)
    }

    func testStrictDecoderPreservesUnsupportedTypeRawBytesWithoutWatts() throws {
        let response = validResponse(sequence: 1, pstrStatus: .unsupportedType)
        guard case let .response(decoded) = PowerObservationV5Decoder().decode(
            frame: try encoded(response),
            expectedClientSequence: 1
        ) else { return XCTFail("response should decode") }
        XCTAssertTrue(decoded.partial)
        XCTAssertEqual(decoded.key("PSTR")?.rawBytesHex, "00002042")
        XCTAssertNil(decoded.key("PSTR")?.decodedWatts)
    }

    func testStrictDecoderRejectsInvalidRawHex() throws {
        var object = try responseObject(validResponse(sequence: 1))
        var keys = try XCTUnwrap(object["keys"] as? [[String: Any]])
        keys[0]["rawBytesHex"] = "not-hex"
        object["keys"] = keys
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try JSONSerialization.data(withJSONObject: object),
                expectedClientSequence: 1
            ),
            .malformed(.invalidKey)
        )
    }

    func testValidPartialV5IsAuthoritativeAndNeverFallsBack() throws {
        let transport = FakeTransport([
            .frame(try encoded(validResponse(sequence: 4, pstrStatus: .keyUnavailable))),
            .frame(legacyFrame(adapter: 1, system: 2)),
        ])
        let result = PowerObservationV5Client(transport: transport).fetch(clientSequence: 4)
        guard case let .v5(response) = result else {
            return XCTFail("partial v5 must remain authoritative")
        }
        XCTAssertTrue(response.partial)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testNoV5ResponsePerformsExactlyOneV4Fallback() throws {
        let transport = FakeTransport([
            .noResponse,
            .frame(legacyFrame(adapter: 30, system: 20)),
        ])
        let result = PowerObservationV5Client(transport: transport).fetch(clientSequence: 8)
        guard case let .legacyV4(power) = result else {
            return XCTFail("expected legacy fallback")
        }
        XCTAssertEqual(power.adapterW, 30)
        XCTAssertEqual(power.systemW, 20)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.maximums, [4_096, 512])
    }

    func testUnversionedOldHelperRejectionPerformsOneV4Fallback() throws {
        let oldRejection = try JSONSerialization.data(withJSONObject: [
            "ok": false,
            "error": "rejected",
        ])
        let transport = FakeTransport([
            .frame(oldRejection),
            .frame(legacyFrame(adapter: nil, system: 18)),
        ])
        guard case let .legacyV4(power) = PowerObservationV5Client(
            transport: transport
        ).fetch(clientSequence: 11) else {
            return XCTFail("expected fallback")
        }
        XCTAssertNil(power.adapterW)
        XCTAssertEqual(power.systemW, 18)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testRealOldHelperUnversionedEOFPerformsExactlyOneV4Fallback() throws {
        let server = try RealUnixSocketServer(responses: [
            Data(#"{"ok":false,"error":"malformed"}"#.utf8),
            legacyFrame(adapter: 30, system: 20) + Data([UInt8(ascii: "\n")]),
        ])
        server.start()

        let result = PowerObservationV5Client(
            transport: UnixSocketPowerObservationTransport(socketPath: server.path),
            timeoutSeconds: 1
        ).fetch(clientSequence: 21)
        XCTAssertTrue(server.waitForCompletion())

        guard case let .legacyV4(power) = result else {
            return XCTFail("complete unversioned EOF must retry v4 exactly once, got \(result)")
        }
        XCTAssertEqual(power.adapterW, 30)
        XCTAssertEqual(power.systemW, 20)
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(try protocolVersion(in: server.requests[0]), 5)
        XCTAssertEqual(try protocolVersion(in: server.requests[1]), 4)
    }

    func testRealCompleteMalformedClaimedV5EOFNeverFallsBack() throws {
        let server = try RealUnixSocketServer(responses: [
            Data(#"{"_wattsonProtocol":5,"ok":false}"#.utf8),
            legacyFrame(adapter: 1, system: 1) + Data([UInt8(ascii: "\n")]),
        ])
        server.start()

        XCTAssertEqual(
            PowerObservationV5Client(
                transport: UnixSocketPowerObservationTransport(socketPath: server.path),
                timeoutSeconds: 1
            ).fetch(clientSequence: 22),
            .failed(.invalidV5(.missingTopLevelField))
        )
        XCTAssertTrue(server.waitForCompletion())
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(try protocolVersion(in: server.requests[0]), 5)
    }

    func testRealTruncatedClaimedV5EOFNeverFallsBack() throws {
        let server = try RealUnixSocketServer(responses: [
            Data(#"{"_wattsonProtocol":5,"ok":"#.utf8),
            legacyFrame(adapter: 1, system: 1) + Data([UInt8(ascii: "\n")]),
        ])
        server.start()

        XCTAssertEqual(
            PowerObservationV5Client(
                transport: UnixSocketPowerObservationTransport(socketPath: server.path),
                timeoutSeconds: 1
            ).fetch(clientSequence: 23),
            .failed(.truncatedV5Frame)
        )
        XCTAssertTrue(server.waitForCompletion())
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(try protocolVersion(in: server.requests[0]), 5)
    }

    func testMalformedClaimedV5NeverFallsBack() throws {
        var object = try responseObject(validResponse(sequence: 2))
        object.removeValue(forKey: "keys")
        let transport = FakeTransport([
            .frame(try JSONSerialization.data(withJSONObject: object)),
            .frame(legacyFrame(adapter: 1, system: 1)),
        ])
        XCTAssertEqual(
            PowerObservationV5Client(transport: transport).fetch(clientSequence: 2),
            .failed(.invalidV5(.missingTopLevelField))
        )
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testTruncatedClaimedV5NeverFallsBack() throws {
        let frame = Data(#"{"_wattsonProtocol":5,"ok":true"#.utf8)
        let transport = FakeTransport([
            .frame(frame),
            .frame(legacyFrame(adapter: 1, system: 1)),
        ])
        XCTAssertEqual(
            PowerObservationV5Client(transport: transport).fetch(clientSequence: 2),
            .failed(.invalidV5(.invalidJSON))
        )
        XCTAssertEqual(transport.requests.count, 1)

        let incompleteTransport = FakeTransport([
            .incompleteFrame(frame),
            .frame(legacyFrame(adapter: 1, system: 1)),
        ])
        XCTAssertEqual(
            PowerObservationV5Client(
                transport: incompleteTransport
            ).fetch(clientSequence: 2),
            .failed(.truncatedV5Frame)
        )
        XCTAssertEqual(incompleteTransport.requests.count, 1)

        var maximumBody = try encoded(validResponse(sequence: 2))
        XCTAssertLessThan(maximumBody.count, PowerObservationV5Decoder.maximumFrameBytes)
        maximumBody.append(Data(
            repeating: UInt8(ascii: " "),
            count: PowerObservationV5Decoder.maximumFrameBytes - maximumBody.count
        ))
        XCTAssertEqual(maximumBody.count, PowerObservationV5Decoder.maximumFrameBytes)
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: maximumBody,
                expectedClientSequence: 2
            ),
            .malformed(.frameTooLarge)
        )

        let maximumTransport = FakeTransport([
            .frame(maximumBody),
            .frame(legacyFrame(adapter: 1, system: 1)),
        ])
        XCTAssertEqual(
            PowerObservationV5Client(
                transport: maximumTransport
            ).fetch(clientSequence: 2),
            .failed(.invalidV5(.frameTooLarge))
        )
        XCTAssertEqual(maximumTransport.requests.count, 1)
    }

    func testExplicitV5ConnectionFailureDoesNotFallBack() throws {
        let response = failedResponse(sequence: 12)
        let transport = FakeTransport([
            .frame(try encoded(response)),
            .frame(legacyFrame(adapter: 1, system: 1)),
        ])
        guard case let .v5(decoded) = PowerObservationV5Client(
            transport: transport
        ).fetch(clientSequence: 12) else {
            return XCTFail("valid v5 failure must be returned")
        }
        XCTAssertFalse(decoded.ok)
        XCTAssertTrue(decoded.partial)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testV5ResponseMapsToPhase1SMCObservationWithoutChangingRawValues() throws {
        let response = validResponse(sequence: 3)
        let observation = try response.asSMCObservation()
        XCTAssertEqual(observation.keys.map(\.key), ["PDTR", "PSTR", "PPBR"])
        XCTAssertEqual(observation.key("PDTR")?.decodedWatts, 38)
        XCTAssertEqual(observation.key("PSTR")?.decodedWatts, 32)
        XCTAssertEqual(observation.key("PPBR")?.decodedWatts, 1)
        XCTAssertEqual(observation.key("PSTR")?.rawBytesHex, "00002042")
    }

    // MARK: fixtures

    private func validResponse(
        sequence: UInt64,
        pstrStatus: PowerObservationV5KeyStatus = .present
    ) -> PowerObservationV5Response {
        let pstrPresent = pstrStatus == .present
        let pstrUnsupported = pstrStatus == .unsupportedType
        let pstrType: String? = (pstrPresent || pstrUnsupported) ? "flt " : nil
        let pstrBytes: String? = (pstrPresent || pstrUnsupported) ? "00002042" : nil
        let pstrIssue: String? = pstrPresent ? nil : "fixture unavailable"
        let keys = [
            key("PDTR", source: .smcPDTR, watts: 38, bytes: "00001842"),
            PowerObservationV5Key(
                key: "PSTR",
                source: .smcPSTR,
                status: pstrStatus,
                startedContinuousNanoseconds: 111,
                endedContinuousNanoseconds: 120,
                dataTypeFourCC: pstrType,
                rawBytesHex: pstrBytes,
                decodedWatts: pstrPresent ? 32 : nil,
                ioReturn: nil,
                validationIssue: pstrIssue
            ),
            key("PPBR", source: .smcPPBR, watts: 1, bytes: "0000803F"),
        ]
        return PowerObservationV5Response(
            wattsonProtocol: 5,
            ok: true,
            partial: keys.contains { $0.status != .present },
            clientSequence: sequence,
            clock: "CLOCK_MONOTONIC_RAW",
            error: nil,
            connection: PowerObservationV5Connection(
                status: .opened,
                startedContinuousNanoseconds: 100,
                endedContinuousNanoseconds: 140,
                ioReturn: nil,
                validationIssue: nil
            ),
            keys: keys
        )
    }

    private func failedResponse(sequence: UInt64) -> PowerObservationV5Response {
        PowerObservationV5Response(
            wattsonProtocol: 5,
            ok: false,
            partial: true,
            clientSequence: sequence,
            clock: "CLOCK_MONOTONIC_RAW",
            error: "AppleSMC unavailable",
            connection: PowerObservationV5Connection(
                status: .serviceUnavailable,
                startedContinuousNanoseconds: 100,
                endedContinuousNanoseconds: 100,
                ioReturn: nil,
                validationIssue: "AppleSMC unavailable"
            ),
            keys: ["PDTR", "PSTR", "PPBR"].enumerated().map { index, name in
                PowerObservationV5Key(
                    key: name,
                    source: [ObservationSource.smcPDTR, .smcPSTR, .smcPPBR][index],
                    status: .connectionUnavailable,
                    startedContinuousNanoseconds: 100,
                    endedContinuousNanoseconds: 100,
                    dataTypeFourCC: nil,
                    rawBytesHex: nil,
                    decodedWatts: nil,
                    ioReturn: nil,
                    validationIssue: "AppleSMC unavailable"
                )
            }
        )
    }

    private func key(
        _ name: String,
        source: ObservationSource,
        watts: Double,
        bytes: String
    ) -> PowerObservationV5Key {
        PowerObservationV5Key(
            key: name,
            source: source,
            status: .present,
            startedContinuousNanoseconds: 101,
            endedContinuousNanoseconds: 110,
            dataTypeFourCC: "flt ",
            rawBytesHex: bytes,
            decodedWatts: watts,
            ioReturn: nil,
            validationIssue: nil
        )
    }

    private func encoded(_ response: PowerObservationV5Response) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response)
    }

    private func responseObject(_ response: PowerObservationV5Response) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(response)) as? [String: Any])
    }

    private func legacyFrame(adapter: Double?, system: Double?) -> Data {
        var object: [String: Any] = ["ok": true]
        if let adapter { object["adapterW"] = adapter }
        if let system { object["systemW"] = system }
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func protocolVersion(in request: Data) throws -> Int {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: request) as? [String: Any]
        )
        return try XCTUnwrap((object["_wattsonProtocol"] as? NSNumber)?.intValue)
    }
}
