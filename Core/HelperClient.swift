import Darwin
import Foundation

enum HelperClient {
    static let socketPath = "/var/run/wattson-helper.sock"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    static func send(_ request: [String: Any]) -> [String: Any]? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else { return nil }

        guard let payload = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        let written = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
        guard written == payload.count else { return nil }

        var buffer = [UInt8](repeating: 0, count: 512)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(buffer[0..<count])) as? [String: Any]
    }
}
