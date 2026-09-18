import Foundation

public struct AudioConfig: Codable, Equatable, Sendable {
    public var bookmarkData: Data?
    public var customFileName: String?
    public var volume: Float
    public var loopAudio: Bool
    public var cooldownSeconds: Double
    
    public init(
        bookmarkData: Data? = nil,
        customFileName: String? = nil,
        volume: Float = AppConstants.defaultVolume,
        loopAudio: Bool = false,
        cooldownSeconds: Double = AppConstants.defaultCooldownSeconds
    ) {
        self.bookmarkData = bookmarkData
        self.customFileName = customFileName
        self.volume = volume
        self.loopAudio = loopAudio
        self.cooldownSeconds = cooldownSeconds
    }
    
    public static let `default` = AudioConfig()
}
