import Foundation
import ServiceManagement

/// Registers or unregisters the app as a login item.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("KeepAwake: could not change login item: \(error.localizedDescription)")
        }
        // Read the real state back, in case the change was refused.
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}