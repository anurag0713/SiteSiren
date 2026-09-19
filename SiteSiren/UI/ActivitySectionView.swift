import SwiftUI

public struct ActivitySectionView: View {
    @ObservedObject var activityStore: ActivityStore
    @ObservedObject var protectionManager: ProtectionManager
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    public init(activityStore: ActivityStore, protectionManager: ProtectionManager) {
        self.activityStore = activityStore
        self.protectionManager = protectionManager
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Blocked Attempts")
                        .font(.headline)
                    Text("Showing up to 100 recent blocked connection events (local only)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    protectionManager.simulateBlock(domain: "test-blocked-domain.com", processName: "TestSim")
                }) {
                    Label("Test Siren Alert", systemImage: "bell.badge")
                }
                .buttonStyle(.bordered)
                .help("Simulate a blocked event to test audio playback and cooldown")
                
                Button(role: .destructive, action: {
                    activityStore.clearHistory()
                }) {
                    Label("Clear History", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(activityStore.events.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Events Table / List
            if activityStore.events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No blocked attempts recorded yet.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Text("When a blocked website is accessed in Safari, Chrome, or any app, it will appear here.")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(activityStore.events) { event in
                        HStack(spacing: 16) {
                            Text(timeFormatter.string(from: event.timestamp))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.octagon.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 11))
                                Text(event.domain)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            }
                            
                            Spacer()
                            
                            if let process = event.processName {
                                Text(process)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }
}
