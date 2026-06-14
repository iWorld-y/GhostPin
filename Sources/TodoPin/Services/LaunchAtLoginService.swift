import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "当前系统不支持这个开机启动接口。"
        }
    }
}

enum LaunchAtLoginService {
    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } else {
            throw LaunchAtLoginError.unsupported
        }
    }
}
