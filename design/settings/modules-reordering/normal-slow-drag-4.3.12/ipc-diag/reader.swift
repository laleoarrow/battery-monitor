import Foundation
let shared = URL(fileURLWithPath: CommandLine.arguments[1])
let local = URL(fileURLWithPath: CommandLine.arguments[2])
let a = shared.appendingPathComponent("host-replaced.json")
let b = shared.appendingPathComponent("guest-replaced.json")
let c = local.appendingPathComponent("local.json")
let manager = FileManager.default
func emit(_ value: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([10]))
}
try Data("local-0".utf8).write(to: c, options: .atomic)
let start = ProcessInfo.processInfo.systemUptime
try Data("ready".utf8).write(to: shared.appendingPathComponent("reader-ready"))
var step = 0
while ProcessInfo.processInfo.systemUptime - start < 8 {
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    if elapsed >= Double(step + 1) * 2, step < 2 {
        step += 1
        for path in [b,c] {
            do {
                try Data("guest-\(step)".utf8).write(to: path, options: .atomic)
                try emit(["event":"guest-atomic-replace","name":path.lastPathComponent,"step":step,"epoch":Date().timeIntervalSince1970,"elapsed":elapsed])
            } catch { try emit(["event":"guest-write-error","name":path.lastPathComponent,"error":String(describing:error)]) }
        }
    }
    for path in [a,b,c] {
        do {
            let data = try Data(contentsOf: path)
            let attrs = try manager.attributesOfItem(atPath: path.path)
            try emit(["event":"read","name":path.lastPathComponent,"value":String(data:data,encoding:.utf8) ?? "non-utf8","bytes":data.count,"inode":attrs[.systemFileNumber] ?? NSNull(),"mtimeEpoch":(attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,"epoch":Date().timeIntervalSince1970,"elapsed":elapsed])
        } catch { try emit(["event":"read-error","name":path.lastPathComponent,"error":String(describing:error),"elapsed":elapsed]) }
    }
    Thread.sleep(forTimeInterval: 0.1)
}
