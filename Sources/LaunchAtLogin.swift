import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case needsApproval

    var errorDescription: String? {
        switch self {
        case .needsApproval:
            return "系统还没有允许登录时打开。"
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
            if service.status == .requiresApproval {
                throw LaunchAtLoginError.needsApproval
            }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}
