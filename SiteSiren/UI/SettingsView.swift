import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case protection = "Protection"
    case blockedSites = "Blocked Websites"
    case audio = "Audio"
    case activity = "Activity"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .protection:
            return "shield.lefthalf.filled"
        case .blockedSites:
            return "network.badge.shield.half.filled"
        case .audio:
            return "speaker.wave.3.fill"
        case .activity:
            return "clock.arrow.circlepath"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var protectionManager: ProtectionManager
    @ObservedObject var domainManager: BlockedDomainManager
    @ObservedObject var audioManager: AudioManager
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var activityStore: ActivityStore
    
    @Binding var selectedTab: SettingsTab
    
    public init(
        protectionManager: ProtectionManager,
        domainManager: BlockedDomainManager,
        audioManager: AudioManager,
        appSettings: AppSettings,
        activityStore: ActivityStore,
        selectedTab: Binding<SettingsTab>
    ) {
        self.protectionManager = protectionManager
        self.domainManager = domainManager
        self.audioManager = audioManager
        self.appSettings = appSettings
        self.activityStore = activityStore
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            ProtectionSectionView(
                protectionManager: protectionManager,
                appSettings: appSettings
            )
            .tabItem {
                Label(SettingsTab.protection.rawValue, systemImage: SettingsTab.protection.iconName)
            }
            .tag(SettingsTab.protection)
            
            BlockedSitesSectionView(
                domainManager: domainManager
            )
            .tabItem {
                Label(SettingsTab.blockedSites.rawValue, systemImage: SettingsTab.blockedSites.iconName)
            }
            .tag(SettingsTab.blockedSites)
            
            AudioSectionView(
                audioManager: audioManager
            )
            .tabItem {
                Label(SettingsTab.audio.rawValue, systemImage: SettingsTab.audio.iconName)
            }
            .tag(SettingsTab.audio)
            
            ActivitySectionView(
                activityStore: activityStore,
                protectionManager: protectionManager
            )
            .tabItem {
                Label(SettingsTab.activity.rawValue, systemImage: SettingsTab.activity.iconName)
            }
            .tag(SettingsTab.activity)
        }
        .frame(minWidth: 540, minHeight: 460)
    }
}
