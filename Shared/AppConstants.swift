import Foundation

public enum AppConstants {
    public static let appBundleIdentifier = "com.personal.SiteSiren"
    public static let filterExtensionBundleIdentifier = "com.personal.SiteSiren.filter"
    public static let appGroupIdentifier = "group.com.personal.SiteSiren"
    
    // Darwin notification names for real-time IPC
    public static let domainBlockedDarwinNotification = "com.personal.SiteSiren.domainBlocked"
    public static let rulesUpdatedDarwinNotification = "com.personal.SiteSiren.rulesUpdated"
    
    // File and key names
    public static let blockedDomainsFileName = "blocked_domains.json"
    public static let blockEventsFileName = "block_events.json"
    public static let audioConfigKey = "SiteSirenAudioConfig"
    public static let protectionEnabledKey = "SiteSirenProtectionEnabled"
    
    // Default values
    public static let defaultCooldownSeconds: Double = 2.0
    public static let defaultVolume: Float = 1.0
    public static let maxActivityHistoryCount: Int = 100
    
    // Fallback directory for local development if App Groups are unprovisioned
    public static let fallbackFolderName = "SiteSiren"
}
