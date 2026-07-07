import AppIntents
import Darwin
import Foundation
import IOKit
import SwiftUI
import WidgetKit

private let refreshInterval: TimeInterval = 5 * 60
private let batteryWidgetKind = "BatteryPowerSystemWidget"
private let refreshFeedbackDuration: TimeInterval = 2.5

private struct BatteryWidgetSnapshot: Codable {
    var percent: Int
    var plugged: Bool
    var charging: Bool
    var systemW: Double
    var chargeW: Double
    var dischargeW: Double
    var updatedAt: Double = Date().timeIntervalSince1970

    var totalW: Double {
        max(systemW, 0) + max(chargeW, 0)
    }

    var statusText: String {
        if charging { return "充电中" }
        if plugged { return "已接电" }
        if percent <= 20 { return "低电量" }
        return "电池供电"
    }

    var accentColor: Color {
        if charging { return Color(hex: 0x34E36E) }
        if plugged { return Color(hex: 0x4AA3FF) }
        if percent <= 20 { return Color(hex: 0xFF453A) }
        return Color(hex: 0xA6ABB6)
    }

    var batteryLine: (label: String, value: Double, color: Color) {
        if chargeW > 0.05 {
            return ("充电", chargeW, Color(hex: 0x34E36E))
        }
        if dischargeW > 0.05 {
            return ("放电", dischargeW, percent <= 20 ? Color(hex: 0xFF453A) : Color(hex: 0xF8FAFC))
        }
        return ("电池", 0, Color(hex: 0xA6ABB6))
    }

    static let preview = BatteryWidgetSnapshot(
        percent: 100,
        plugged: true,
        charging: false,
        systemW: 32.7,
        chargeW: 0,
        dischargeW: 0
    )

    static func current() -> BatteryWidgetSnapshot {
        WidgetPowerSampler.sample() ?? loadShared() ?? .preview
    }

    static func loadShared() -> BatteryWidgetSnapshot? {
        let url = realHomeDirectory()
            .appendingPathComponent("Library/Application Support/电池功率", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(BatteryWidgetSnapshot.self, from: data)
    }

    private static func realHomeDirectory() -> URL {
        if let passwd = getpwuid(getuid()),
           let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

// The sandbox denies fork/exec, so unlike the host app the extension cannot
// shell out to ioreg; reading IORegistry properties directly is allowed.
private enum WidgetPowerSampler {
    static func sample() -> BatteryWidgetSnapshot? {
        guard let props = batteryProperties() else {
            return nil
        }

        let percent = intValue(props["CurrentCapacity"])
        let plugged = boolValue(props["ExternalConnected"])
        let charging = boolValue(props["IsCharging"])
        let voltage = intValue(props["Voltage"])
        let amperage = intValue(props["Amperage"])
        let telemetry = intMap(props["PowerTelemetryData"])
        let charger = intMap(props["ChargerData"])

        let chargeW = chargePower(charging: charging, telemetry: telemetry, charger: charger, voltage: voltage, amperage: amperage)
        let systemW: Double
        if let load = telemetry["SystemLoad"] {
            systemW = Double(load) / 1000.0
        } else if let systemIn = telemetry["SystemPowerIn"] {
            systemW = max(Double(systemIn) / 1000.0 - chargeW, 0)
        } else {
            systemW = fallbackPower(voltage: voltage, amperage: amperage)
        }
        let dischargeW = plugged ? 0 : (telemetry["BatteryPower"].map { abs(Double($0) / 1000.0) } ?? fallbackPower(voltage: voltage, amperage: amperage))

        return BatteryWidgetSnapshot(
            percent: percent,
            plugged: plugged,
            charging: charging,
            systemW: systemW,
            chargeW: chargeW,
            dischargeW: dischargeW
        )
    }

    private static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }
        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return props
    }

    // Amperage and friends are stored as raw two's-complement bit patterns, so
    // negative currents surface as huge unsigned numbers (64-bit via NSNumber,
    // 32-bit on older firmware). Battery values never legitimately exceed
    // Int32.max, so anything in the 32-bit wraparound range is negative.
    private static func intValue(_ raw: Any?) -> Int {
        guard let number = raw as? NSNumber else {
            return 0
        }
        var value = number.int64Value
        if value > Int64(Int32.max), value <= Int64(UInt32.max) {
            value -= Int64(UInt32.max) + 1
        }
        return Int(value)
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let flag = raw as? Bool {
            return flag
        }
        return (raw as? NSNumber)?.boolValue ?? false
    }

    private static func intMap(_ raw: Any?) -> [String: Int] {
        guard let dict = raw as? [String: Any] else {
            return [:]
        }
        var values: [String: Int] = [:]
        for (key, value) in dict where value is NSNumber {
            values[key] = intValue(value)
        }
        return values
    }

    private static func fallbackPower(voltage: Int, amperage: Int) -> Double {
        abs(Double(voltage) * Double(amperage) / 1_000_000.0)
    }

    private static func chargePower(charging: Bool, telemetry: [String: Int], charger: [String: Int], voltage: Int, amperage: Int) -> Double {
        guard charging else { return 0 }
        if let chargeVoltage = charger["ChargingVoltage"],
           let current = charger["ChargingCurrent"],
           current > 0 {
            return abs(Double(chargeVoltage) * Double(current) / 1_000_000.0)
        }
        if let batteryPower = telemetry["BatteryPower"] {
            return abs(Double(batteryPower) / 1000.0)
        }
        return fallbackPower(voltage: voltage, amperage: amperage)
    }
}

// Performing an intent keeps the tap inside the extension process and explicitly
// asks WidgetKit to reload this timeline instead of launching the host app.
struct RefreshBatteryWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "刷新电池功率"
    static let description = IntentDescription("立即重新读取电池功率数据并刷新小组件。")

    func perform() async throws -> some IntentResult {
        WidgetRefreshFeedbackStore.markRefreshRequested()
        WidgetCenter.shared.reloadTimelines(ofKind: batteryWidgetKind)
        return .result()
    }
}

private enum WidgetRefreshFeedbackStore {
    private static let lastRefreshRequestKey = "lastRefreshRequestAt"

    static func markRefreshRequested(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastRefreshRequestKey)
        UserDefaults.standard.synchronize()
    }

    static func lastRefreshRequestAt() -> Double {
        UserDefaults.standard.double(forKey: lastRefreshRequestKey)
    }

    static func shouldShowFeedback(at date: Date = Date()) -> Bool {
        let lastRequestAt = lastRefreshRequestAt()
        guard lastRequestAt > 0 else {
            return false
        }
        return date.timeIntervalSince1970 - lastRequestAt <= refreshFeedbackDuration
    }
}

private struct BatteryWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BatteryWidgetSnapshot
    let showsRefreshFeedback: Bool
    let refreshAnimationID: Double
}

private struct BatteryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryWidgetEntry {
        BatteryWidgetEntry(date: Date(), snapshot: .preview, showsRefreshFeedback: false, refreshAnimationID: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? BatteryWidgetSnapshot.preview : BatteryWidgetSnapshot.current()
        completion(BatteryWidgetEntry(date: Date(), snapshot: snapshot, showsRefreshFeedback: false, refreshAnimationID: WidgetRefreshFeedbackStore.lastRefreshRequestAt()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = BatteryWidgetSnapshot.current()
        let showFeedback = WidgetRefreshFeedbackStore.shouldShowFeedback(at: now)
        let refreshAnimationID = WidgetRefreshFeedbackStore.lastRefreshRequestAt()
        var entries = [
            BatteryWidgetEntry(date: now, snapshot: snapshot, showsRefreshFeedback: showFeedback, refreshAnimationID: refreshAnimationID)
        ]
        if showFeedback {
            entries.append(
                BatteryWidgetEntry(
                    date: now.addingTimeInterval(refreshFeedbackDuration),
                    snapshot: snapshot,
                    showsRefreshFeedback: false,
                    refreshAnimationID: refreshAnimationID
                )
            )
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshInterval))))
    }
}

private struct BatteryPowerSystemWidget: Widget {
    let kind = batteryWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryWidgetProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("电池功率")
        .description("显示当前电量和功率，点按立即刷新。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct StatusDot: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hex: 0x4AA3FF))
            .frame(width: size, height: size)
    }
}

private struct FlipNumberText: View {
    let text: String
    let size: CGFloat
    let color: Color
    let minimumScale: CGFloat
    let isRefreshing: Bool
    let refreshAnimationID: Double

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
            .background {
                if isRefreshing {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: 0x4AA3FF).opacity(0.12))
                        .padding(.horizontal, -4)
                        .padding(.vertical, -2)
                }
            }
            .overlay {
                if isRefreshing {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, -4)
                }
            }
            .rotation3DEffect(
                .degrees(isRefreshing ? -7 : 0),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.45
            )
            .id(refreshAnimationID)
            .transition(.asymmetric(insertion: .push(from: .top), removal: .push(from: .bottom)))
    }
}

private struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryWidgetEntry

    var body: some View {
        Button(intent: RefreshBatteryWidgetIntent()) {
            Group {
                switch family {
                case .systemMedium:
                    mediumLayout
                default:
                    smallLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .containerBackground(Color(hex: 0x17191F), for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                totalPowerNumber(size: 32)
                Text("W")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xA6ABB6))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                percentView(size: 20)
                statusView(size: 14)
                batteryLineView
            }
        }
        .padding(16)
    }

    private var mediumLayout: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    totalPowerNumber(size: 40)
                    Text("W")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0xA6ABB6))
                }
                statusView(size: 15)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                percentView(size: 28)
                metricRow(label: "负载", value: entry.snapshot.systemW, color: Color(hex: 0xF8FAFC))
                batteryLineView
            }
        }
        .padding(18)
    }

    private func percentView(size: CGFloat) -> some View {
        HStack(spacing: 12) {
            StatusDot(size: size * 0.34)
            FlipNumberText(
                text: "\(entry.snapshot.percent)%",
                size: size,
                color: entry.snapshot.accentColor,
                minimumScale: 0.75,
                isRefreshing: entry.showsRefreshFeedback,
                refreshAnimationID: entry.refreshAnimationID
            )
        }
    }

    private func statusView(size: CGFloat) -> some View {
        Text(entry.snapshot.statusText)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: 0xF8FAFC))
            .minimumScaleFactor(0.8)
        .lineLimit(1)
    }

    private func totalPowerNumber(size: CGFloat) -> some View {
        FlipNumberText(
            text: String(format: "%.1f", entry.snapshot.totalW),
            size: size,
            color: entry.snapshot.accentColor,
            minimumScale: 0.7,
            isRefreshing: entry.showsRefreshFeedback,
            refreshAnimationID: entry.refreshAnimationID
        )
    }

    private var batteryLineView: some View {
        let line = entry.snapshot.batteryLine
        return metricRow(label: line.label, value: line.value, color: line.color)
    }

    private func metricRow(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(Color(hex: 0xA6ABB6))
            Text(String(format: "%.1f W", value))
                .foregroundStyle(color)
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }
}

@main
struct BatteryPowerWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteryPowerSystemWidget()
    }
}
