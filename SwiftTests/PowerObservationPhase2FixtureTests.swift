import XCTest
@testable import Wattson

final class PowerObservationPhase2FixtureTests: XCTestCase {
    func testCompleteV5FixtureDecodesWithThreePresentKeys() throws {
        guard case let .response(response) = PowerObservationV5Decoder().decode(
            frame: try fixture("v5-complete", extension: "json"),
            expectedClientSequence: 41
        ) else { return XCTFail("complete fixture must decode") }
        XCTAssertFalse(response.partial)
        XCTAssertEqual(response.keys.map(\.status), [.present, .present, .present])
    }

    func testPartialV5FixtureRemainsAuthoritativeAndPreservesRawPSTR() throws {
        guard case let .response(response) = PowerObservationV5Decoder().decode(
            frame: try fixture("v5-partial", extension: "json"),
            expectedClientSequence: 41
        ) else { return XCTFail("partial fixture must decode") }
        XCTAssertTrue(response.partial)
        XCTAssertEqual(response.key("PSTR")?.status, .unsupportedType)
        XCTAssertEqual(response.key("PSTR")?.rawBytesHex, "00000842")
        XCTAssertNil(response.key("PSTR")?.decodedWatts)
    }

    func testConnectionFailureFixtureIsValidV5AndDoesNotImplyFallback() throws {
        guard case let .response(response) = PowerObservationV5Decoder().decode(
            frame: try fixture("v5-connection-failure", extension: "json"),
            expectedClientSequence: 41
        ) else { return XCTFail("failure fixture must decode as v5") }
        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.partial)
        XCTAssertEqual(response.keys.map(\.status), [
            .connectionUnavailable, .connectionUnavailable, .connectionUnavailable,
        ])
    }

    func testTruncatedV5FixtureIsMalformedAndNotLegacy() throws {
        XCTAssertEqual(
            PowerObservationV5Decoder().decode(
                frame: try fixture("v5-truncated", extension: "json.partial"),
                expectedClientSequence: 41
            ),
            .malformed(.invalidJSON)
        )
    }

    private func fixture(_ name: String, extension ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "Fixtures/PowerResolution"
        ))
        var data = try Data(contentsOf: url)
        if data.last == UInt8(ascii: "\n") { data.removeLast() }
        return data
    }
}
