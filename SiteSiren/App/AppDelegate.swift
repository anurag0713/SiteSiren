import SwiftUI
import AppKit
import os.log

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    public let protectionManager = ProtectionManager()
    public let domainManager = BlockedDomainManager()
    public let audioManager = AudioManager()
    public let appSettings = AppSettings()
    public let activityStore = ActivityStore()
    
    private var menuBarController: MenuBarController?
    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "AppDelegate")
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("SiteSiren launched.")
        
        // Wire cross-component dependencies
        protectionManager.audioManager = audioManager
        protectionManager.activityStore = activityStore
        domainManager.onRulesUpdated = { [weak self] in
            self?.protectionManager.refreshPAC()
        }
        
        // Setup menu bar item and popover
        menuBarController = MenuBarController(
            protectionManager: protectionManager,
            domainManager: domainManager,
            audioManager: audioManager,
            appSettings: appSettings,
            activityStore: activityStore
        )
    }
    
    public func openSettings(tab: SettingsTab = .protection) {
        menuBarController?.openSettingsWindow(tab: tab)
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Continue running in background menu bar even when settings window is closed
        return false
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        protectionManager.shutdown()
    }
}
