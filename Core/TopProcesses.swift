import CoreFoundation
import Foundation

struct EnergyProcess: Equatable, Sendable {
    let pid: Int32
    let name: String
    let energyImpact: Double
    let cpuPercent: Double
    let idleWakeupsPerSecond: Double
}

enum TopProcessesState: Equatable, Sendable {
    case loading
    case ready([EnergyProcess])
    case unavailable
}

struct TopProcessesClient: Sendable {
    static let maximumProcesses = 10
    static let maximumResponseBytes = 4_096

    let transport: any PowerObservationFrameTransport

    func fetch() -> TopProcessesState {
        // This separate response bound leaves the existing v4 operations at
        // 512 bytes. Older helpers reject the fixed operation and show unavailable.
        let request = Data(#"{"_wattsonProtocol":4,"op":"getTopProcesses"}"#.utf8)
            + Data([UInt8(ascii: "\n")])
        guard case let .frame(frame) = transport.exchange(
            request: request,
            maximumResponseBytes: Self.maximumResponseBytes,
            timeoutSeconds: 6
        ) else { return .unavailable }
        return Self.decode(frame)
    }

    static func decode(_ frame: Data) -> TopProcessesState {
        guard frame.count < maximumResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
              HelperClient.strictJSONBool(object["ok"]) == true,
              let rows = object["processes"] as? [[String: Any]],
              rows.count <= maximumProcesses else { return .unavailable }

        var processes: [EnergyProcess] = []
        var seenPIDs: Set<Int32> = []
        let controls = CharacterSet.controlCharacters.subtracting(
            CharacterSet(charactersIn: "\u{200C}\u{200D}")
        )
        for row in rows {
            guard let pidNumber = row["pid"] as? NSNumber,
                  CFGetTypeID(pidNumber) != CFBooleanGetTypeID(),
                  let pid = Int32(exactly: pidNumber.doubleValue), pid > 0,
                  seenPIDs.insert(pid).inserted,
                  let name = row["name"] as? String,
                  !name.isEmpty, name.count <= 64, name.utf8.count <= 96,
                  name == name.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.unicodeScalars.contains(where: controls.contains),
                  let score = nonnegativeNumber(row["energyImpact"]),
                  let cpuPercent = nonnegativeNumber(row["cpuPercent"]),
                  let wakeupsPerSecond = nonnegativeNumber(row["idleWakeupsPerSecond"]) else {
                return .unavailable
            }
            processes.append(EnergyProcess(
                pid: pid,
                name: name,
                energyImpact: score,
                cpuPercent: cpuPercent,
                idleWakeupsPerSecond: wakeupsPerSecond
            ))
        }
        return .ready(processes.sorted {
            $0.energyImpact == $1.energyImpact
                ? $0.pid < $1.pid : $0.energyImpact > $1.energyImpact
        })
    }

    private static func nonnegativeNumber(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
}

extension HelperClient {
    static func topProcesses() -> TopProcessesState {
        TopProcessesClient(transport: UnixSocketPowerObservationTransport()).fetch()
    }
}
