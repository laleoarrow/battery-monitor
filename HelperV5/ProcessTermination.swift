import CoreFoundation
import Darwin
import Foundation

public struct HelperProcessIdentity: Equatable, Sendable {
    public let pid: Int32
    public let startedAt: UInt64
    public let auditToken: Data

    public init(pid: Int32, startedAt: UInt64, auditToken: Data) {
        self.pid = pid
        self.startedAt = startedAt
        self.auditToken = auditToken
    }

    public static func decodeRequest(_ object: [String: Any]) -> HelperProcessIdentity? {
        guard Set(object.keys) == ["_wattsonProtocol", "op", "pid", "startedAt", "auditToken"],
              let version = object["_wattsonProtocol"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 4,
              object["op"] as? String == "forceQuitProcess",
              let number = object["pid"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let pid = Int32(exactly: number.doubleValue), pid > 1,
              let rawStart = object["startedAt"] as? String,
              let startedAt = UInt64(rawStart), startedAt > 0, String(startedAt) == rawStart,
              let rawToken = object["auditToken"] as? String,
              let data = Data(base64Encoded: rawToken), data.base64EncodedString() == rawToken,
              let token = HelperProcessAuditToken(data: data), token.pid == pid else { return nil }
        return HelperProcessIdentity(pid: pid, startedAt: startedAt, auditToken: data)
    }

    public func belongsToConsoleUser(_ uid: uid_t) -> Bool {
        guard pid > 1, startedAt > 0, uid != 0,
              let token = HelperProcessAuditToken(data: auditToken) else { return false }
        return token.pid == pid && token.effectiveUID == uid && token.realUID == uid
    }
}

/// The public audit_token_t ABI is eight UInt32 words. These are the same
/// fields exposed by libbsm's audit_token_to_{euid,ruid,pid} accessors; keep
/// interpretation here while passing all 32 kernel-issued bytes unchanged.
struct HelperProcessAuditToken {
    var value: audit_token_t

    init?(data: Data) {
        guard data.count == 32, MemoryLayout<audit_token_t>.size == 32 else { return nil }
        value = audit_token_t()
        _ = withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0) }
    }

    var effectiveUID: uid_t { value.val.1 }
    var realUID: uid_t { value.val.3 }
    var pid: Int32 { Int32(bitPattern: value.val.5) }
}

public enum HelperProcessTerminationResult: String, Equatable, Sendable {
    case signalSent, alreadyExited, identityChanged, notPermitted, unavailable, failed

    public var workerExitCode: Int32 {
        switch self {
        case .signalSent: return 0
        case .alreadyExited: return 31
        case .identityChanged: return 32
        case .notPermitted: return 33
        case .unavailable: return 34
        case .failed: return 35
        }
    }

    public init(workerExitCode: Int32?) {
        switch workerExitCode {
        case 0: self = .signalSent
        case 31: self = .alreadyExited
        case 32: self = .identityChanged
        case 33: self = .notPermitted
        case 34: self = .unavailable
        default: self = .failed
        }
    }

    public var responseLine: Data {
        let ok = self == .signalSent || self == .alreadyExited
        return Data("{\"ok\":\(ok),\"result\":\"\(rawValue)\"}\n".utf8)
    }
}

public enum HelperProcessReadFailure: Error { case alreadyExited, notPermitted, unavailable }

public protocol HelperProcessTerminationBackend {
    var signalIsAvailable: Bool { get }
    var consoleUser: uid_t? { get }
    var realUser: uid_t { get }
    var effectiveUser: uid_t { get }
    func identity(for pid: Int32) -> Result<HelperProcessIdentity, HelperProcessReadFailure>
    /// proc_signal_with_audittoken returns errno itself, not -1 + errno.
    func sendKill(to identity: HelperProcessIdentity) -> Int32?
}

public enum HelperProcessTermination {
    public static func forceQuit(
        _ identity: HelperProcessIdentity, expectedUID: uid_t,
        backend: any HelperProcessTerminationBackend = SystemHelperProcessTerminationBackend()
    ) -> HelperProcessTerminationResult {
        // This entry point must execute only after the fixed worker has
        // permanently relinquished root. The parent helper never signals.
        guard expectedUID != 0, backend.consoleUser == expectedUID,
              backend.realUser == expectedUID, backend.effectiveUser == expectedUID,
              identity.belongsToConsoleUser(expectedUID) else { return .notPermitted }
        guard backend.signalIsAvailable else { return .unavailable }
        switch backend.identity(for: identity.pid) {
        case .failure(.alreadyExited): return .alreadyExited
        case .failure(.notPermitted): return .notPermitted
        case .failure(.unavailable): return .unavailable
        case .success(let current):
            guard current == identity else { return .identityChanged }
        }
        guard backend.consoleUser == expectedUID,
              backend.realUser == expectedUID, backend.effectiveUser == expectedUID else { return .notPermitted }
        // The full audit token atomically selects the original kernel process
        // incarnation even if it exits or its PID is reused after our read.
        switch backend.sendKill(to: identity) {
        case 0: return .signalSent
        case ESRCH: return .alreadyExited
        case EPERM, EACCES: return .notPermitted
        case ENOTSUP, ENOSYS: return .unavailable
        case nil: return .unavailable
        default: return .failed
        }
    }
}

public struct SystemHelperProcessTerminationBackend: HelperProcessTerminationBackend {
    private typealias SignalFunction = @convention(c) (UnsafeMutablePointer<audit_token_t>?, Int32) -> Int32
    // Public libproc API is resolved at runtime: older systems retain their
    // process readings and simply do not offer a termination control.
    private static let signalFunction: SignalFunction? = {
        guard let library = dlopen("/usr/lib/libproc.dylib", RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let symbol = dlsym(library, "proc_signal_with_audittoken") else {
            dlclose(library)
            return nil
        }
        // Retain this one library reference for the process lifetime so the
        // function pointer never outlives its image.
        return unsafeBitCast(symbol, to: SignalFunction.self)
    }()

    public init() {}
    public var signalIsAvailable: Bool { Self.signalFunction != nil }
    public var realUser: uid_t { getuid() }
    public var effectiveUser: uid_t { geteuid() }
    public var consoleUser: uid_t? {
        var info = stat()
        return stat("/dev/console", &info) == 0 ? info.st_uid : nil
    }

    public func identity(for pid: Int32) -> Result<HelperProcessIdentity, HelperProcessReadFailure> {
        guard pid > 1 else { return .failure(.notPermitted) }
        func startedAt() -> UInt64? {
            var usage = rusage_info_v0()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V0, $0) }
            }
            guard result == 0, usage.ri_proc_exit_abstime == 0, usage.ri_proc_start_abstime > 0 else { return nil }
            return usage.ri_proc_start_abstime
        }
        guard let start = startedAt() else {
            return .failure(errno == ESRCH ? .alreadyExited : errno == EPERM ? .notPermitted : .unavailable)
        }
        var namePort: mach_port_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &namePort) == KERN_SUCCESS,
              namePort != MACH_PORT_NULL else { return .failure(.unavailable) }
        defer { mach_port_deallocate(mach_task_self_, namePort) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(namePort, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count == 8,
              let endStart = startedAt(), endStart == start else { return .failure(.unavailable) }
        let data = withUnsafeBytes(of: token) { Data($0) }
        guard let audit = HelperProcessAuditToken(data: data), audit.pid == pid else { return .failure(.unavailable) }
        return .success(HelperProcessIdentity(pid: pid, startedAt: start, auditToken: data))
    }

    public func sendKill(to identity: HelperProcessIdentity) -> Int32? {
        guard let function = Self.signalFunction, var token = HelperProcessAuditToken(data: identity.auditToken),
              token.pid == identity.pid else { return nil }
        return function(&token.value, SIGKILL)
    }
}
