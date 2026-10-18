import Darwin
import Foundation
import XCTest
@testable import Wattson

final class ProcessTerminationTests: XCTestCase {
    private func identity(pid: Int32 = 42, start: UInt64 = UInt64.max) -> ProcessIdentity {
        var token = audit_token_t()
        token.val = (501, 501, 20, 501, 20, UInt32(bitPattern: pid), 0, 7)
        return ProcessIdentity(pid: pid, startedAt: start, auditToken: withUnsafeBytes(of: token) { Data($0) })
    }

    private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func testFixedRequestPreservesFullPrecisionIdentityAndAcceptsKnownResults() {
        struct Transport: PowerObservationFrameTransport {
            let identity: ProcessIdentity
            let result: String
            func exchange(request: Data, maximumResponseBytes: Int, timeoutSeconds: Int) -> PowerObservationFrameExchange {
                XCTAssertEqual(request.last, UInt8(ascii: "\n"))
                let object = try! JSONSerialization.jsonObject(with: request) as! [String: Any]
                XCTAssertEqual(Set(object.keys), ["_wattsonProtocol", "op", "pid", "startedAt", "auditToken"])
                XCTAssertEqual(object["op"] as? String, "forceQuitProcess")
                XCTAssertEqual(object["_wattsonProtocol"] as? Int, 4)
                XCTAssertEqual(object["pid"] as? Int32, identity.pid)
                XCTAssertEqual(object["startedAt"] as? String, String(UInt64.max))
                XCTAssertEqual(object["auditToken"] as? String, identity.auditToken.base64EncodedString())
                XCTAssertEqual(maximumResponseBytes, 512)
                XCTAssertEqual(timeoutSeconds, 3)
                let ok = ["signalSent", "alreadyExited"].contains(result)
                return .frame(Data("{\"ok\":\(ok),\"result\":\"\(result)\"}".utf8))
            }
        }
        let cases: [(String, ProcessTerminationResult)] = [
            ("signalSent", .signalSent), ("alreadyExited", .alreadyExited), ("identityChanged", .identityChanged),
            ("notPermitted", .notPermitted), ("unavailable", .unavailable), ("failed", .failed),
        ]
        for (raw, result) in cases {
            XCTAssertEqual(ProcessTerminationClient(transport: Transport(identity: identity(), result: raw))
                .forceQuitProcess(identity()), result)
        }
    }

    func testRejectsMalformedLegacyAndContradictoryTerminationResponses() {
        for object: [String: Any] in [
            ["ok": true], ["ok": false, "error": "rejected"],
            ["ok": 1, "result": "signalSent"], ["ok": true, "result": "failed"],
            ["ok": false, "result": "signalSent"], ["ok": true, "result": "alreadyExited", "pid": 42],
            ["ok": false, "result": "unknown"], ["ok": true, "result": NSNull()],
        ] { XCTAssertEqual(ProcessTerminationClient.decode(data(object)), .unavailable) }
        XCTAssertEqual(ProcessTerminationClient.decode(Data(repeating: 32, count: 512)), .unavailable)
    }

    func testIdentityValidationDoesNotSendInvalidRequests() {
        struct NoTransport: PowerObservationFrameTransport {
            func exchange(request: Data, maximumResponseBytes: Int, timeoutSeconds: Int) -> PowerObservationFrameExchange {
                XCTFail("Invalid identity must never reach IPC")
                return .noResponse
            }
        }
        for invalid in [
            identity(pid: 1), identity(pid: -1), identity(start: 0),
            ProcessIdentity(pid: 42, startedAt: 1, auditToken: Data(repeating: 0, count: 31)),
        ] {
            XCTAssertEqual(ProcessTerminationClient(transport: NoTransport()).forceQuitProcess(invalid), .unavailable)
        }
    }

    func testOlderReadingsRemainCompatibleAndMalformedPresentIdentityIsRejected() {
        let original: [String: Any] = ["pid": 42, "name": "Renderer", "energyImpact": 12, "cpuPercent": 12, "idleWakeupsPerSecond": 0]
        func decode(_ identity: Any?) -> TopProcessesState {
            var row = original
            if let identity { row["terminationIdentity"] = identity }
            return TopProcessesClient.decode(data(["ok": true, "processes": [row]]))
        }
        let expected = EnergyProcess(pid: 42, name: "Renderer", energyImpact: 12, cpuPercent: 12, idleWakeupsPerSecond: 0)
        XCTAssertEqual(decode(nil), .ready([expected]))
        let valid: [String: Any] = ["startedAt": String(UInt64.max), "auditToken": identity().auditToken.base64EncodedString()]
        guard case let .ready(rows) = decode(valid) else { return XCTFail("valid identity") }
        XCTAssertEqual(rows.first?.terminationIdentity, identity())
        for invalid in [NSNull(), "bad", [:]] as [Any] { XCTAssertEqual(decode(invalid), .unavailable) }
        for (field, value) in [
            ("startedAt", "01" as Any), ("startedAt", "+1"), ("startedAt", "0"), ("startedAt", UInt64.max),
            ("startedAt", "18446744073709551616"), ("startedAt", " 1"),
            ("auditToken", String(identity().auditToken.base64EncodedString().dropLast())),
            ("auditToken", identity(pid: 43).auditToken.base64EncodedString()),
            ("auditToken", Data(repeating: 0, count: 31).base64EncodedString()),
        ] {
            var invalid = valid
            invalid[field] = value
            XCTAssertEqual(decode(invalid), .unavailable, "\(field): \(value)")
        }
        var extra = valid; extra["signal"] = 9
        XCTAssertEqual(decode(extra), .unavailable)
    }
}
