import Foundation
import XCTest
@testable import Wattson

final class TopProcessesTests: XCTestCase {
    private func frame(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func row(pid: Any = 42, name: String = "Renderer", score: Any = 12.5,
                     cpu: Any? = nil, wakeups: Any = 0) -> [String: Any] {
        ["pid": pid, "name": name, "energyImpact": score,
         "cpuPercent": cpu ?? score, "idleWakeupsPerSecond": wakeups]
    }

    func testDecodesRelativeScoresAndSortsAllTenBeforeDisplayLimit() {
        let rows = (1...10).map { row(pid: $0, score: Double($0)) }
        guard case let .ready(processes) = TopProcessesClient.decode(frame(["ok": true, "processes": rows])) else {
            return XCTFail("Expected all ten ranked processes")
        }
        XCTAssertEqual(processes.count, 10)
        XCTAssertEqual(processes.map(\.pid), Array((1...10).reversed()).map(Int32.init))
        XCTAssertEqual(processes.first?.energyImpact, 10)
        XCTAssertEqual(processes.first?.cpuPercent, 10)
        XCTAssertEqual(processes.first?.idleWakeupsPerSecond, 0)
    }

    func testRejectsMissingOldHelperMalformedAndOversizedReplies() {
        for object: [String: Any] in [
            ["ok": false, "error": "rejected"], ["ok": true],
            ["ok": 1, "processes": [row()]],
            ["ok": true, "processes": Array(repeating: row(), count: 11)],
            ["ok": true, "processes": [row(pid: true)]],
            ["ok": true, "processes": [row(pid: 4.5)]],
            ["ok": true, "processes": [row(pid: 0)]],
            ["ok": true, "processes": [row(score: true)]],
            ["ok": true, "processes": [row(score: -1)]],
            ["ok": true, "processes": [row(score: "NaN")]],
            ["ok": true, "processes": [row(cpu: true)]],
            ["ok": true, "processes": [row(cpu: -1)]],
            ["ok": true, "processes": [row(cpu: "NaN")]],
            ["ok": true, "processes": [row(wakeups: true)]],
            ["ok": true, "processes": [row(wakeups: -1)]],
            ["ok": true, "processes": [row(wakeups: "Infinity")]],
            ["ok": true, "processes": [row().filter { $0.key != "cpuPercent" }]],
            ["ok": true, "processes": [row().filter { $0.key != "idleWakeupsPerSecond" }]],
            ["ok": true, "processes": [row(name: "bad\nname")]],
            ["ok": true, "processes": [row(name: " padded ")]],
            ["ok": true, "processes": [row(), row()]],
        ] {
            XCTAssertEqual(TopProcessesClient.decode(frame(object)), .unavailable)
        }
        XCTAssertEqual(TopProcessesClient.decode(Data(repeating: 32, count: 4_096)), .unavailable)
        XCTAssertEqual(TopProcessesClient.decode(Data("{truncated".utf8)), .unavailable)
        XCTAssertEqual(TopProcessesClient.decode(frame(["ok": true, "processes": []])), .ready([]))
        for field in ["energyImpact", "cpuPercent", "idleWakeupsPerSecond"] {
            let invalid = #"{"ok":true,"processes":[{"pid":42,"name":"Test","energyImpact":0,"cpuPercent":0,"idleWakeupsPerSecond":0}]}"#
                .replacingOccurrences(of: "\"\(field)\":0", with: "\"\(field)\":1e309")
            XCTAssertEqual(TopProcessesClient.decode(Data(invalid.utf8)), .unavailable)
        }
    }

    func testNameLimitCountsUTF8BytesAsWellAsCharacters() {
        let allowed = row(name: String(repeating: "é", count: 48))
        guard case .ready = TopProcessesClient.decode(frame(["ok": true, "processes": [allowed]])) else {
            return XCTFail("A 96-byte, 48-character name must remain valid")
        }
        let family = row(name: String(repeating: "👨‍👩‍👧‍👦", count: 3))
        guard case .ready = TopProcessesClient.decode(frame(["ok": true, "processes": [family]])) else {
            return XCTFail("Joiners inside a bounded grapheme must remain valid")
        }
        for name in [String(repeating: "é", count: 49), String(repeating: "a", count: 65)] {
            XCTAssertEqual(TopProcessesClient.decode(frame(["ok": true, "processes": [row(name: name)]])), .unavailable)
        }
    }

    func testFetchUsesFixedReadOnlyOperationAndItsOwnBound() {
        struct Transport: PowerObservationFrameTransport {
            func exchange(request: Data, maximumResponseBytes: Int, timeoutSeconds: Int) -> PowerObservationFrameExchange {
                XCTAssertEqual(String(decoding: request, as: UTF8.self), "{\"_wattsonProtocol\":4,\"op\":\"getTopProcesses\"}\n")
                XCTAssertEqual(maximumResponseBytes, 4_096)
                XCTAssertEqual(timeoutSeconds, 6)
                return .frame(Data(#"{"ok":true,"processes":[{"pid":42,"name":"Idle","energyImpact":0,"cpuPercent":0,"idleWakeupsPerSecond":0}]}"#.utf8))
            }
        }
        XCTAssertEqual(TopProcessesClient(transport: Transport()).fetch(), .ready([
            EnergyProcess(pid: 42, name: "Idle", energyImpact: 0, cpuPercent: 0, idleWakeupsPerSecond: 0),
        ]))
    }
}
