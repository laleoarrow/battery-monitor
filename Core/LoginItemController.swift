import Foundation
import ServiceManagement

enum LoginItemState: Equatable {
    case unsupported
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// Keeps the menu in sync with macOS instead of mirroring the choice in a
/// preference that can drift when the user changes Login Items in Settings.
enum LoginItemController {
    static var state: LoginItemState {
        guard #available(macOS 13.0, *) else { return .unsupported }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    @discardableResult
    static func toggle() throws -> LoginItemState {
        guard #available(macOS 13.0, *) else { return .unsupported }

        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            try service.unregister()
        case .notRegistered:
            try service.register()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }

        let updated = state
        if updated == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        return updated
    }
}
