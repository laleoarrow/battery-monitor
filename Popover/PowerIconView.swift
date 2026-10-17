import AppKit

/// Retains resolved colors so telemetry-only updates reuse the same artwork.
final class PowerIconImageView: NSImageView {
    private struct Configuration: Equatable {
        let symbol: String
        let ink: NSColor
        let accent: NSColor
        let side: CGFloat
        let inset: CGFloat
        let increasedContrast: Bool
    }

    private var rendered: Configuration?
#if DEBUG
    private(set) var renderCountForTest = 0
#endif

    @discardableResult
    func configurePowerIcon(symbol: String, description: String, accent: NSColor,
                            side: CGFloat, inset: CGFloat) -> Bool {
        guard Self.descriptor(for: symbol) != nil else {
            rendered = nil
            return false
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let configuration = Configuration(
                symbol: symbol,
                ink: PopoverStyle.neutral.usingColorSpace(.sRGB) ?? PopoverStyle.neutral,
                accent: accent.usingColorSpace(.sRGB) ?? accent,
                side: side, inset: inset,
                increasedContrast: PopoverStyle.isHighContrast(effectiveAppearance)
            )
            if rendered != configuration {
                image = Self.image(for: symbol, side: side, inset: inset,
                                   ink: configuration.ink, accent: configuration.accent,
                                   increasedContrast: configuration.increasedContrast)
                contentTintColor = nil
                rendered = configuration
#if DEBUG
                renderCountForTest += 1
#endif
            }
            image?.accessibilityDescription = description
        }
        return true
    }

    static func image(for symbol: String, side: CGFloat = 32, inset: CGFloat = 4,
                      ink: NSColor = .black, accent: NSColor = .black,
                      increasedContrast: Bool = false) -> NSImage? {
        guard let (icon, fraction) = descriptor(for: symbol) else { return nil }
        return ModuleIconArtwork.powerImage(
            for: icon, side: side, inset: inset, chargeFraction: fraction,
            ink: ink, accent: accent, increasedContrast: increasedContrast
        )
    }

    static func batterySymbol(percent: Int) -> String {
        switch percent {
        case ..<25: return "battery.25"
        case ..<50: return "battery.50"
        case ..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    private static func descriptor(for symbol: String) -> (ModuleIconArtwork.PowerIcon, CGFloat)? {
        switch symbol {
        case "cpu": return (.system, 1)
        case "powerplug": return (.adapter, 1)
        case "powerplug.slash": return (.disconnected, 1)
        case "battery.25": return (.battery, 0.25)
        case "battery.50": return (.battery, 0.5)
        case "battery.75": return (.battery, 0.75)
        case "battery.100": return (.battery, 1)
        case "battery.100.bolt": return (.charging, 1)
        default: return nil
        }
    }
}
