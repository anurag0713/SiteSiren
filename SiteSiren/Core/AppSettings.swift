import Foundation
import ServiceManagement
import Combine
import os.log

@MainActor
public final class AppSettings: ObservableObject {
    @Published public var launchAtLogin: Bool = false {
        didSet {
            updateLaunchAtLogin(launchAtLogin)
        }
    }
    
    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "AppSettings")
    
    public init() {
        checkLaunchAtLoginStatus()
    }
    
    public func checkLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        self.launchAtLogin = (status == .enabled)
        logger.info("Current SMAppService status: \(status.rawValue)")
    }
    
    private func updateLaunchAtLogin(_ enable: Bool) {
        let current = SMAppService.mainApp.status == .enabled
        guard current != enable else { return }
        
        do {
            if enable {
                try SMAppService.mainApp.register()
                logger.info("Registered app for Launch at Login.")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Unregistered app from Launch at Login.")
            }
        } catch {
            logger.error("Failed to update Launch at Login: \(error.localizedDescription)")
            // Revert state if registration failed
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
