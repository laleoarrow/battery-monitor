import AppKit

/// Launches the shipping popover view with telemetry sampled from this Mac.
///
/// This exists so website and release screenshots can be sourced from the
/// actual AppKit hierarchy instead of a hand-drawn approximation. It performs
/// no mutations: the helper is only queried for cached presentation state.
@main
private enum CaptureRealPopover {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        guard let snapshot = BatterySampler.sample() else {
            fputs("Wattson capture requires a readable Mac battery.\n", stderr)
            exit(2)
        }

        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 28, height: 22))
        button.image = BatteryIcon.image(
            for: snapshot,
            mode: EnergyModeController.current,
            pressed: false,
            style: .wattson
        )
        button.imagePosition = .imageOnly
        button.toolTip = "Wattson real-popover capture"

        let anchorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 28, height: 22),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        anchorWindow.isOpaque = false
        anchorWindow.backgroundColor = .clear
        anchorWindow.hasShadow = false
        anchorWindow.level = .statusBar
        anchorWindow.contentView?.addSubview(button)
        if let screen = NSScreen.main {
            anchorWindow.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX,
                y: screen.visibleFrame.maxY - 22
            ))
        }
        anchorWindow.orderFrontRegardless()

        let popover = PopoverController()
        popover.update(
            snapshot: snapshot,
            history: Array(repeating: snapshot.totalInputW, count: 24),
            peak: max(snapshot.totalInputW, 1),
            degraded: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            popover.toggle(relativeTo: button)
        }

        // Keep both AppKit objects alive while the screenshot tool captures the
        // popover. The process is intentionally terminated by the caller.
        withExtendedLifetime((anchorWindow, button, popover)) {
            app.run()
        }
    }
}
