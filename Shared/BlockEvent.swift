import Foundation

public struct BlockEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let domain: String
    public let timestamp: Date
    public let processName: String?
    public let remoteAddress: String?
    
    public init(
        id: UUID = UUID(),
        domain: String,
        timestamp: Date = Date(),
        processName: String? = nil,
        remoteAddress: String? = nil
    ) {
        self.id = id
        self.domain = domain
        self.timestamp = timestamp
        self.processName = processName
        self.remoteAddress = remoteAddress
    }
}
