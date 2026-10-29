import Foundation
import ServiceManagement

public protocol LaunchAtLoginManaging {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public enum LaunchAtLoginError: Error, Equatable, Sendable, LocalizedError {
    case requiresApproval

    public var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Launch at login requires approval in System Settings > General > Login Items."
        }
    }
}

public final class LaunchAtLoginManager: LaunchAtLoginManaging {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                throw LaunchAtLoginError.requiresApproval
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
