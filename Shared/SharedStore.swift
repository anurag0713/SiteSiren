import Foundation
import os.log

public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()
    
    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "SharedStore")
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.personal.SiteSiren.SharedStore", qos: .userInitiated)
    
    private init() {
        createBaseDirectoryIfNeeded()
    }
    
    // MARK: - Directory Resolution
    
    public var baseDirectory: URL {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) {
            return groupURL
        }
        
        // Fallback for local development or unsigned testing
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fallbackDir = appSupport.appendingPathComponent(AppConstants.fallbackFolderName, isDirectory: true)
        return fallbackDir
    }
    
    private func createBaseDirectoryIfNeeded() {
        let dir = baseDirectory
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    public var userDefaults: UserDefaults {
        if let groupDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) {
            return groupDefaults
        }
        return UserDefaults.standard
    }
    
    // MARK: - Blocked Domains
    
    private var blockedDomainsURL: URL {
        baseDirectory.appendingPathComponent(AppConstants.blockedDomainsFileName)
    }
    
    public func saveBlockedDomains(_ rules: [DomainRule]) {
        queue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(rules)
                try data.write(to: blockedDomainsURL, options: [.atomic])
                logger.info("Saved \(rules.count) blocked domain rules to \(self.blockedDomainsURL.path)")
            } catch {
                logger.error("Failed to save blocked domains: \(error.localizedDescription)")
            }
        }
    }
    
    public func loadBlockedDomains() -> [DomainRule] {
        queue.sync {
            guard fileManager.fileExists(atPath: blockedDomainsURL.path) else {
                return []
            }
            do {
                let data = try Data(contentsOf: blockedDomainsURL)
                let rules = try JSONDecoder().decode([DomainRule].self, from: data)
                return rules
            } catch {
                logger.error("Failed to load blocked domains: \(error.localizedDescription)")
                return []
            }
        }
    }
    
    public func loadBlockedDomainStrings() -> [String] {
        loadBlockedDomains().map { $0.domain }
    }
    
    // MARK: - Block Events / Activity
    
    private var blockEventsURL: URL {
        baseDirectory.appendingPathComponent(AppConstants.blockEventsFileName)
    }
    
    public func recordBlockEvent(_ event: BlockEvent) {
        queue.sync {
            var events: [BlockEvent] = []
            if fileManager.fileExists(atPath: blockEventsURL.path),
               let data = try? Data(contentsOf: blockEventsURL),
               let existing = try? JSONDecoder().decode([BlockEvent].self, from: data) {
                events = existing
            }
            
            // Prepend latest event, cap at max limit
            events.insert(event, at: 0)
            if events.count > AppConstants.maxActivityHistoryCount {
                events = Array(events.prefix(AppConstants.maxActivityHistoryCount))
            }
            
            do {
                let data = try JSONEncoder().encode(events)
                try data.write(to: blockEventsURL, options: [.atomic])
            } catch {
                logger.error("Failed to record block event: \(error.localizedDescription)")
            }
        }
    }
    
    public func loadBlockEvents() -> [BlockEvent] {
        queue.sync {
            guard fileManager.fileExists(atPath: blockEventsURL.path),
                  let data = try? Data(contentsOf: blockEventsURL),
                  let events = try? JSONDecoder().decode([BlockEvent].self, from: data) else {
                return []
            }
            return events
        }
    }
    
    public func clearBlockEvents() {
        queue.sync {
            try? fileManager.removeItem(at: blockEventsURL)
        }
    }
    
    // MARK: - Audio Config
    
    public func saveAudioConfig(_ config: AudioConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            userDefaults.set(data, forKey: AppConstants.audioConfigKey)
        } catch {
            logger.error("Failed to save audio config: \(error.localizedDescription)")
        }
    }
    
    public func loadAudioConfig() -> AudioConfig {
        guard let data = userDefaults.data(forKey: AppConstants.audioConfigKey),
              let config = try? JSONDecoder().decode(AudioConfig.self, from: data) else {
            return .default
        }
        return config
    }
    
    // MARK: - Protection State
    
    public func setProtectionEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: AppConstants.protectionEnabledKey)
    }
    
    public func isProtectionEnabled() -> Bool {
        if userDefaults.object(forKey: AppConstants.protectionEnabledKey) == nil {
            return true // Default enabled on first launch
        }
        return userDefaults.bool(forKey: AppConstants.protectionEnabledKey)
    }
    
    // MARK: - Darwin Notifications (Cross-process IPC)
    
    public static func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }
    
    public static func postBlockEventOccurred() {
        postDarwinNotification(AppConstants.domainBlockedDarwinNotification)
    }
    
    public static func postRulesUpdated() {
        postDarwinNotification(AppConstants.rulesUpdatedDarwinNotification)
    }
}
