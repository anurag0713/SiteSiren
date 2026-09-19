import SwiftUI

public struct ProtectionSectionView: View {
    @ObservedObject var protectionManager: ProtectionManager
    @ObservedObject var appSettings: AppSettings

    public init(protectionManager: ProtectionManager, appSettings: AppSettings) {
        self.protectionManager = protectionManager
        self.appSettings = appSettings
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Protection Status")
                            .font(.headline)
                        Text(protectionManager.status.displayText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    StatusBadge(
                        status: protectionManager.status,
                        isEnabled: protectionManager.isProtectionEnabled
                    )
                }
                .padding(.vertical, 4)

                Toggle(isOn: Binding(
                    get: { protectionManager.isProtectionEnabled },
                    set: { _ in protectionManager.toggleProtection() }
                )) {
                    VStack(alignment: .leading) {
                        Text("Protection Enabled")
                            .fontWeight(.medium)
                        Text("When enabled, access to blocked domains is blocked and alerts sound.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, 4)
            } header: {
                Text("Content Filter Status")
            }

            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PAC Proxy — No Signing Required")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("SiteSiren uses a system-wide Proxy Auto-Configuration (PAC) script to block domains. This works across all browsers without a paid Apple Developer account. Chrome extensions that control their own proxy (e.g. some VPNs) may bypass this filter when active.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("How It Works")
            }

            Section {
                Toggle(isOn: $appSettings.launchAtLogin) {
                    VStack(alignment: .leading) {
                        Text("Launch at Login")
                            .fontWeight(.medium)
                        Text("Start SiteSiren automatically in the menu bar when you log in.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("System Integration")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
