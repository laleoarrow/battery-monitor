import AppKit
import Darwin
import IOKit

/// A small, reviewable attachment for public bug reports. Never export the
/// complete IORegistry, environment, logs, or installation paths.
enum FeedbackDiagnostics {
    static let filename = "Wattson-Diagnostics.txt"

    struct Context {
        let version: String
        let build: String
        let settings: [String: String]
        let accessibility: [String: String]
        let displayedSnapshot: PowerSnapshot?
        var displayedReadingIsStale = false
    }

    struct Report {
        let text: String
        let issueURL: URL
    }

    private static let batteryKeys = [
        "CurrentCapacity", "MaxCapacity", "AppleRawCurrentCapacity",
        "AppleRawMaxCapacity", "DesignCapacity", "Voltage", "Amperage",
        "InstantAmperage", "AvgTimeToEmpty", "AvgTimeToFull", "InstantTimeToEmpty",
        "TimeRemaining", "CycleCount", "Temperature", "VirtualTemperature",
        "ExternalConnected", "ExternalChargeCapable", "IsCharging", "FullyCharged",
    ]
    private static let telemetryKeys = [
        "SystemPowerIn", "SystemLoad", "BatteryPower",
        "SystemPowerInAccumulatorCount", "SystemLoadAccumulatorCount",
        "BatteryPowerAccumulatorCount",
    ]

    /// Capture preferences and accessibility on the UI thread before the
    /// bounded helper probe and IORegistry reads run on a worker queue.
    static func context(
        currentVersion: String,
        displayedSnapshot: PowerSnapshot?,
        displayedReadingIsStale: Bool,
        effectiveAppearance: String
    ) -> Context {
        let workspace = NSWorkspace.shared
        return Context(
            version: currentVersion,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
            settings: [
                "effectiveAppearance": effectiveAppearance,
                "theme": Settings.colorScheme.rawValue,
                "liquidGlassEnabled": String(Settings.liquidGlassEnabled),
                "liquidGlassActive": String(Settings.usesLiquidGlass),
                "liquidGlassStyle": Settings.liquidGlassStyle.rawValue,
                "transparencyPercent": String(Int((Settings.liquidGlassTransparency * 100).rounded())),
                "inAppLogo": Settings.inAppLogoStyle.rawValue,
                "dockIcon": Settings.dockIconStyle.rawValue,
                "menuBarIcon": Settings.menuBarIconStyle.rawValue,
                "menuBarPercentage": String(Settings.showsMenuBarPercentage),
                "automaticUpdateChecks": String(Settings.checksForUpdatesOnLaunch),
            ].merging(Dictionary(uniqueKeysWithValues: Settings.Module.allCases.map {
                ("module.\($0.rawValue)", String(Settings.isModuleVisible($0)))
            }), uniquingKeysWith: { first, _ in first }),
            accessibility: [
                "reduceMotion": String(workspace.accessibilityDisplayShouldReduceMotion),
                "reduceTransparency": String(workspace.accessibilityDisplayShouldReduceTransparency),
                "increaseContrast": String(workspace.accessibilityDisplayShouldIncreaseContrast),
            ],
            displayedSnapshot: displayedSnapshot,
            displayedReadingIsStale: displayedReadingIsStale
        )
    }

    static func collect(_ context: Context) -> Report {
        let info = ProcessInfo.processInfo
#if arch(arm64)
        let architecture = "arm64"
#else
        let architecture = "x86_64"
#endif
        let system: [String: String] = [
            "macOS": info.operatingSystemVersionString,
            "macOSBuild": systemString("kern.osversion") ?? "unavailable",
            "macModel": systemString("hw.model") ?? "unavailable",
            "cpuModel": systemString("machdep.cpu.brand_string") ?? "unavailable",
            "hardwareMachine": systemString("hw.machine") ?? "unavailable",
            "appleSiliconCapable": systemInteger("hw.optional.arm64").map { String($0 == 1) } ?? "unavailable",
            "processArchitecture": architecture,
            "translatedProcess": systemInteger("sysctl.proc_translated").map { String($0 == 1) } ?? "unavailable",
            "physicalMemoryBytes": String(info.physicalMemory),
            "lowPowerMode": String(info.isLowPowerModeEnabled),
            "collectedAtUTC": ISO8601DateFormatter().string(from: Date()),
        ]
        let socketPresent = HelperClient.isInstalled
        let receiptURL = URL(fileURLWithPath: "/var/db/receipts/com.leoarrow.wattson.pkg.plist")
        let receipt = (try? Data(contentsOf: receiptURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        let helper = [
            "socketPresent": String(socketPresent),
            "health": socketPresent
                ? (HelperClient.isHealthy() ? "healthy" : "unreachable or incompatible")
                : "not checked (socket absent)",
            "packageReceiptPresent": String(FileManager.default.fileExists(atPath: receiptURL.path)),
            "packageVersion": receipt?["PackageVersion"] as? String ?? "unavailable",
        ]
        return makeReport(
            context: context,
            system: system,
            helper: helper,
            batteryProperties: readBatteryProperties()
        )
    }

    static func makeReport(
        context: Context,
        system: [String: String],
        helper: [String: String],
        batteryProperties: [String: Any]?
    ) -> Report {
        var sections = [
            "Wattson feedback diagnostics (schema 1)",
            "Review this file before attaching it to a public GitHub issue.\n"
                + "Contains app/system versions, Mac model, preferences and battery readings.\n"
                + "Excludes serial numbers, account/host names, paths, logs and usage history.",
            section("Application", ["version": context.version, "build": context.build]),
            section("System", system),
            section("Settings", context.settings),
            section("Accessibility", context.accessibility),
            section("Helper and installation", helper),
        ]
        if let snapshot = context.displayedSnapshot {
            let readingTitle = context.displayedReadingIsStale
                ? "Displayed reading (last known; current telemetry unavailable)"
                : "Displayed reading (current)"
            sections.append(section(readingTitle, [
                "batteryPercent": String(snapshot.percent),
                "powerState": String(describing: snapshot.state),
                "plugged": String(snapshot.plugged),
                "adapterWatts": String(snapshot.adapterW),
                "batteryWattsSigned": String(snapshot.batteryW),
                "systemWatts": String(snapshot.systemW),
                "deviceOutputWatts": snapshot.deviceOutputW.map { String($0) } ?? "unavailable",
                "deviceOutputIsComplete": String(snapshot.deviceOutputIsComplete),
                "temperatureC": snapshot.temperatureC.map { String($0) } ?? "unavailable",
                "cycleCount": String(snapshot.cycleCount),
                "lowPowerMode": String(snapshot.lowPowerMode),
                "estimatedRuntimeMinutes": snapshot.estimatedRuntimeMinutes.map { String($0) } ?? "unavailable",
            ]))
        } else {
            sections.append("[Displayed reading]\nunavailable")
        }
        sections.append(section("Battery inputs read for this report (raw firmware units)",
            safeBatteryValues(batteryProperties)))
        return Report(
            text: sections.joined(separator: "\n\n") + "\n",
            issueURL: issueURL(version: context.version, macOS: system["macOS"] ?? "unavailable")
        )
    }

    /// Only explicitly selected numeric/Boolean fields can enter the attachment.
    static func safeBatteryValues(_ properties: [String: Any]?) -> [String: String] {
        guard let properties else { return ["batteryService": "unavailable"] }
        var values = ["batteryService": "available"]
        for key in batteryKeys { values[key] = numericDescription(properties[key]) }
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        for key in telemetryKeys {
            values["PowerTelemetryData.\(key)"] = numericDescription(telemetry[key])
        }
        return values
    }

    static func issueURL(version: String, macOS: String) -> URL {
        var url = URLComponents(string: "https://github.com/laleoarrow/battery-monitor/issues/new")!
        url.queryItems = [URLQueryItem(name: "body", value:
            "## What happened\n\nDescribe the bug or suggestion.\n\n"
                + "## Steps to reproduce\n\n1. \n2. \n\n"
                + "## Expected behavior\n\n\n"
                + "## Environment\n\nWattson: \(version)\nmacOS: \(macOS)\n\n"
                + "## Diagnostics\n\nReview and drag \(filename) into this issue to attach it. "
                + "You can also add a screenshot. GitHub issues and attachments are public.\n"
        )]
        // GitHub parses the query as a form; preserve literal plus signs in
        // version strings rather than letting them become spaces.
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return url.url!
    }

    private static func section(_ title: String, _ values: [String: String]) -> String {
        "[\(title)]\n" + values.keys.sorted().map { "\($0): \(values[$0]!)" }.joined(separator: "\n")
    }

    private static func numericDescription(_ value: Any?) -> String {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return "unavailable" }
        return number.stringValue
    }

    private static func readBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var properties: [String: Any] = [:]
        for key in batteryKeys + ["PowerTelemetryData"] {
            properties[key] = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue()
        }
        return properties
    }

    private static func systemString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func systemInteger(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
