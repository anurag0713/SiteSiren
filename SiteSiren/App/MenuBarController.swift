import SwiftUI
import AppKit
import Combine

@MainActor
public final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    
    private let protectionManager: ProtectionManager
    private let domainManager: BlockedDomainManager
    private let audioManager: AudioManager
    private let appSettings: AppSettings
    private let activityStore: ActivityStore
    
    private var settingsWindowController: NSWindowController?
    private var selectedSettingsTab: SettingsTab = .protection
    
    public init(
        protectionManager: ProtectionManager,
        domainManager: BlockedDomainManager,
        audioManager: AudioManager,
        appSettings: AppSettings,
        activityStore: ActivityStore
    ) {
        self.protectionManager = protectionManager
        self.domainManager = domainManager
        self.audioManager = audioManager
        self.appSettings = appSettings
        self.activityStore = activityStore
        super.init()
        setupStatusItem()
        setupPopover()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "SiteSiren")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        
        audioManager.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let button = self?.statusItem?.button else { return }
                let iconName = isPlaying ? "speaker.wave.3.fill" : "bell.badge.fill"
                let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SiteSiren")
                image?.isTemplate = true
                button.image = image
            }
            .store(in: &cancellables)
    }
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 320)
        
        let contentView = MenuBarPopoverView(
            protectionManager: protectionManager,
            domainManager: domainManager,
            audioManager: audioManager,
            onOpenSettings: { [weak self] tab in
                self?.popover?.performClose(nil)
                self?.openSettingsWindow(tab: tab)
            }
        )
        
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Bring app to activation policy if needed so popover responds immediately
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    public func openSettingsWindow(tab: SettingsTab = .protection) {
        self.selectedSettingsTab = tab
        
        if let existing = settingsWindowController?.window {
            // Update root view with selected tab
            updateSettingsWindowView(window: existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("SiteSirenSettingsWindow")
        window.title = "SiteSiren Settings"
        window.isReleasedWhenClosed = false
        
        updateSettingsWindowView(window: window)
        
        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func updateSettingsWindowView(window: NSWindow) {
        let tabBinding = Binding<SettingsTab>(
            get: { self.selectedSettingsTab },
            set: { self.selectedSettingsTab = $0 }
        )
        
        let settingsView = SettingsView(
            protectionManager: protectionManager,
            domainManager: domainManager,
            audioManager: audioManager,
            appSettings: appSettings,
            activityStore: activityStore,
            selectedTab: tabBinding
        )
        window.contentView = NSHostingView(rootView: settingsView)
    }
}
