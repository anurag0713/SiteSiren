import SwiftUI

public struct StatusBadge: View {
    public let status: FilterExtensionStatus
    public let isEnabled: Bool

    public init(status: FilterExtensionStatus, isEnabled: Bool) {
        self.status = status
        self.isEnabled = isEnabled
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(indicatorColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(indicatorColor.opacity(0.12))
        .cornerRadius(6)
    }

    private var statusText: String {
        guard isEnabled else { return "Protection Paused" }
        switch status {
        case .active: return "Protection Active"
        case .paused: return "Protection Paused"
        }
    }

    private var indicatorColor: Color {
        guard isEnabled else { return .orange }
        switch status {
        case .active: return .green
        case .paused: return .orange
        }
    }
}
