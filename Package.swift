// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Wattson",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "Wattson", targets: ["Wattson"]),
        .executable(name: "wattson-helper", targets: ["WattsonHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "Wattson",
            path: ".",
            exclude: [
                ".DS_Store",
                ".agent",
                ".codex",
                ".github",
                ".superpowers",
                "AGENTS.md",
                "BatteryPowerApp.entitlements",
                "BatteryPowerWidgetExtension.entitlements",
                "BatteryPowerWidgetExtension.swift",
                "BatteryPowerWidgetExtension.xcodeproj",
                "HANDOFF.md",
                "Helper",
                "HelperV5",
                "HelperV5Tests",
                "Packaging",
                "README.md",
                "Support",
                "SwiftTests",
                "VERSION",
                "WidgetExtensionInfo.plist",
                "__pycache__",
                "battery_monitor.py",
                "design",
                "design-qa.md",
                "dist",
                "docs",
                "script",
                "scripts",
                "tests",
                "website",
            ],
            sources: [
                "Core",
                "MenuBar",
                "Popover",
                "main.swift",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "WattsonHelperV5Support",
            path: "HelperV5"
        ),
        .executableTarget(
            name: "WattsonHelper",
            dependencies: ["WattsonHelperV5Support"],
            path: "Helper",
            exclude: ["com.leoarrow.wattson.helper.plist"],
            sources: ["wattson-helper.swift"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "WattsonHelperV5SupportTests",
            dependencies: ["WattsonHelperV5Support"],
            path: "HelperV5Tests"
        ),
        .testTarget(
            name: "WattsonTests",
            dependencies: ["Wattson"],
            path: "SwiftTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
