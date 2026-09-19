import Foundation
import os.log

/// Represents the current state of the PAC-based local content filter.
public enum FilterExtensionStatus: Equatable {
    case active
    case paused

    public var displayText: String {
        switch self {
        case .active:  return "Protection Active"
        case .paused:  return "Protection Paused"
        }
    }
}

@MainActor
public final class ProtectionManager: NSObject, ObservableObject {
    @Published public private(set) var isProtectionEnabled: Bool = true
    @Published public private(set) var status: FilterExtensionStatus = .paused

    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "ProtectionManager")
    private var darwinObserverRegistered = false
    private let localFilter = LocalFilterEngine()

    public weak var audioManager: AudioManager?
    public weak var activityStore: ActivityStore?

    public override init() {
        super.init()
        self.isProtectionEnabled = SharedStore.shared.isProtectionEnabled()
        setupLocalFilter()
        registerRulesUpdatedObserver()
        if self.isProtectionEnabled {
            self.localFilter.start()
            self.status = .active
        } else {
            self.status = .paused
        }
    }

    private func setupLocalFilter() {
        localFilter.onBlockDetected = { [weak self] domain in
            guard let self = self else { return }
            let event = BlockEvent(
                domain: domain,
                timestamp: Date(),
                processName: "Browser"
            )
            SharedStore.shared.recordBlockEvent(event)
            self.audioManager?.handleBlockEvent(domain: domain)
            self.activityStore?.refresh()
        }
    }

    public func shutdown() {
        localFilter.stop()
    }

    public func refreshPAC() {
        guard isProtectionEnabled else { return }
        localFilter.refreshPAC()
    }

    // MARK: - Protection Control

    public func toggleProtection() {
        if isProtectionEnabled {
            disableProtection()
        } else {
            enableProtection()
        }
    }

    public func enableProtection() {
        isProtectionEnabled = true
        SharedStore.shared.setProtectionEnabled(true)
        SharedStore.postRulesUpdated()

        localFilter.start()
        status = .active
        logger.info("Protection enabled.")
    }

    public func disableProtection() {
        isProtectionEnabled = false
        SharedStore.shared.setProtectionEnabled(false)
        SharedStore.postRulesUpdated()

        localFilter.stop()
        status = .paused
        logger.info("Protection paused.")
    }

    // MARK: - Darwin Notification Observer (rules-updated IPC)

    /// Observes the rulesUpdated Darwin notification so that if another process
    /// (e.g. a future CLI companion) updates the blocked-domain list, the PAC
    /// script is refreshed without requiring a full app restart.
    private func registerRulesUpdatedObserver() {
        guard !darwinObserverRegistered else { return }
        darwinObserverRegistered = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                let manager = Unmanaged<ProtectionManager>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleRulesUpdatedNotification()
                }
            },
            AppConstants.rulesUpdatedDarwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func handleRulesUpdatedNotification() {
        logger.notice("rulesUpdated Darwin notification received — refreshing PAC...")
        refreshPAC()
    }

    // MARK: - Test Helper

    /// Simulates a block event so you can verify audio and cooldown logic
    /// without needing to actually visit a blocked site.
    public func simulateBlock(domain: String, processName: String? = "TestBrowser") {
        let event = BlockEvent(
            domain: domain,
            timestamp: Date(),
            processName: processName
        )
        SharedStore.shared.recordBlockEvent(event)
        audioManager?.handleBlockEvent(domain: domain)
        activityStore?.refresh()
    }
}
