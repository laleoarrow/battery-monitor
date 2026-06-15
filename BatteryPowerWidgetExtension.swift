import Foundation
import Darwin
import SwiftUI
import WidgetKit

private let refreshInterval: TimeInterval = 60

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

private struct BatteryWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BatteryWidgetSnapshot
}

private struct BatteryWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryWidgetEntry {
        BatteryWidgetEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? BatteryWidgetSnapshot.preview : (BatteryWidgetSnapshot.loadShared() ?? .preview)
        completion(BatteryWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryWidgetEntry>) -> Void) {
        let now = Date()
        let entry = BatteryWidgetEntry(date: now, snapshot: BatteryWidgetSnapshot.loadShared() ?? .preview)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshInterval))))
    }
}

private struct BatteryPowerSystemWidget: Widget {
    let kind = "BatteryPowerSystemWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteryWidgetProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("电池功率")
        .description("显示当前电量和功率快照。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .containerBackground(Color(hex: 0x17191F), for: .widget)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", entry.snapshot.totalW))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.snapshot.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("W")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xA6ABB6))
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                percentView(size: 20)
                Text(entry.snapshot.statusText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xF8FAFC))
                batteryLineView
            }
        }
        .padding(16)
    }

    private var mediumLayout: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: "%.1f W", entry.snapshot.totalW))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.snapshot.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.snapshot.statusText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xF8FAFC))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 10) {
                percentView(size: 28)
                metricRow(label: "负载", value: entry.snapshot.systemW, color: Color(hex: 0xF8FAFC))
                batteryLineView
            }
        }
        .padding(18)
    }

    private func percentView(size: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.snapshot.accentColor)
                .frame(width: size * 0.34, height: size * 0.34)
                .shadow(color: entry.snapshot.accentColor.opacity(0.45), radius: 5)
            Text("\(entry.snapshot.percent)%")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(entry.snapshot.accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
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
