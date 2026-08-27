import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LaunchAtLoginRegistrationIssue: Equatable {
    case readOnlyVolume
}

protocol LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus { get }
    var registrationIssue: LaunchAtLoginRegistrationIssue? { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

struct LaunchAtLoginService: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    var registrationIssue: LaunchAtLoginRegistrationIssue? {
        let values = try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly == true ? .readOnlyVolume : nil
    }

    func register() throws {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard SMAppService.mainApp.status != .notRegistered else { return }
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
