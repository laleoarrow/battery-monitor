import CoreFoundation
import Foundation
import Darwin

struct ProcessIdentity: Equatable, Hashable, Sendable {
    let pid: Int32
    let startedAt: UInt64
    let auditToken: Data

    var isValid: Bool {
        guard pid > 1, startedAt > 0, auditToken.count == 32,
              MemoryLayout<audit_token_t>.size == 32 else { return false }
        var token = audit_token_t()
        _ = withUnsafeMutableBytes(of: &token) { auditToken.copyBytes(to: $0) }
        return Int32(bitPattern: token.val.5) == pid
    }

    static func decode(pid: Int32, object: [String: Any]) -> ProcessIdentity? {
        guard Set(object.keys) == ["startedAt", "auditToken"],
              let rawStart = object["startedAt"] as? String,
              let startedAt = UInt64(rawStart), startedAt > 0,
              String(startedAt) == rawStart,
              let rawToken = object["auditToken"] as? String,
              let token = Data(base64Encoded: rawToken), token.count == 32,
              token.base64EncodedString() == rawToken, pid > 1,
              MemoryLayout<audit_token_t>.size == 32 else { return nil }
        var audit = audit_token_t()
        _ = withUnsafeMutableBytes(of: &audit) { token.copyBytes(to: $0) }
        guard Int32(bitPattern: audit.val.5) == pid else { return nil }
        return ProcessIdentity(pid: pid, startedAt: startedAt, auditToken: token)
    }
}

enum ProcessTerminationResult: Equatable, Sendable {
    case signalSent, alreadyExited, identityChanged, notPermitted, unavailable, failed
}

struct ProcessTerminationClient: Sendable {
    let transport: any PowerObservationFrameTransport

    func forceQuitProcess(_ identity: ProcessIdentity) -> ProcessTerminationResult {
        guard identity.isValid,
              var request = try? JSONSerialization.data(withJSONObject: [
                  "_wattsonProtocol": 4, "op": "forceQuitProcess", "pid": identity.pid,
                  "startedAt": String(identity.startedAt), "auditToken": identity.auditToken.base64EncodedString(),
              ]) else { return .unavailable }
        request.append(UInt8(ascii: "\n"))
        guard case let .frame(frame) = transport.exchange(
            request: request, maximumResponseBytes: 512, timeoutSeconds: 3
        ) else { return .unavailable }
        return Self.decode(frame)
    }

    static func decode(_ frame: Data) -> ProcessTerminationResult {
        guard frame.count < 512,
              let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
              Set(object.keys) == ["ok", "result"],
              let ok = HelperClient.strictJSONBool(object["ok"]),
              let raw = object["result"] as? String else { return .unavailable }
        let result: ProcessTerminationResult
        switch raw {
        case "signalSent": result = .signalSent
        case "alreadyExited": result = .alreadyExited
        case "identityChanged": result = .identityChanged
        case "notPermitted": result = .notPermitted
        case "unavailable": result = .unavailable
        case "failed": result = .failed
        default: return .unavailable
        }
        guard ok == (result == .signalSent || result == .alreadyExited) else { return .unavailable }
        return result
    }
}

extension HelperClient {
    static func forceQuitProcess(_ identity: ProcessIdentity) -> ProcessTerminationResult {
        ProcessTerminationClient(transport: UnixSocketPowerObservationTransport()).forceQuitProcess(identity)
    }
}
