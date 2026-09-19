import SwiftUI
import AppKit

public struct MenuBarPopoverView: View {
    @ObservedObject var protectionManager: ProtectionManager
    @ObservedObject var domainManager: BlockedDomainManager
    @ObservedObject var audioManager: AudioManager
    
    var onOpenSettings: ((SettingsTab) -> Void)?
    
    public init(
        protectionManager: ProtectionManager,
        domainManager: BlockedDomainManager,
        audioManager: AudioManager,
        onOpenSettings: ((SettingsTab) -> Void)? = nil
    ) {
        self.protectionManager = protectionManager
        self.domainManager = domainManager
        self.audioManager = audioManager
        self.onOpenSettings = onOpenSettings
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16, weight: .bold))
                Text("SiteSiren")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                StatusBadge(
                    status: protectionManager.status,
                    isEnabled: protectionManager.isProtectionEnabled
                )
            }
            
            Divider()
            
            // Info Summary
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Blocked Sites:")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Spacer()
                    Text("\(domainManager.blockedDomains.count)")
                        .fontWeight(.semibold)
                        .font(.system(size: 13))
                }
                
                HStack {
                    Text("Current Audio:")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    Spacer()
                    Text(audioManager.currentAudioDisplayName)
                        .fontWeight(.semibold)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                if let warning = audioManager.audioStatusMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 4)
            
            Divider()
            
            // Prominent Stop Audio Alert button when playing
            if audioManager.isPlaying {
                Button(action: {
                    audioManager.stop()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Stop Playing Audio")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Action Buttons
            VStack(spacing: 6) {
                Button(action: {
                    onOpenSettings?(.blockedSites)
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Manage Blocked Sites")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                
                Button(action: {
                    onOpenSettings?(.audio)
                }) {
                    HStack {
                        Image(systemName: "speaker.wave.2")
                        Text("Choose Audio")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                
                Button(action: {
                    onOpenSettings?(.protection)
                }) {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                
                Divider()
                
                Button(action: {
                    protectionManager.toggleProtection()
                }) {
                    HStack {
                        Image(systemName: protectionManager.isProtectionEnabled ? "pause.circle" : "play.circle")
                        Text(protectionManager.isProtectionEnabled ? "Pause Protection" : "Resume Protection")
                        Spacer()
                    }
                    .foregroundColor(protectionManager.isProtectionEnabled ? .orange : .green)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit SiteSiren")
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
