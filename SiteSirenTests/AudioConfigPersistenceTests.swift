import XCTest
@testable import SiteSiren

final class AudioConfigPersistenceTests: XCTestCase {
    
    func testAudioConfigCodable() throws {
        var original = AudioConfig()
        original.volume = 0.75
        original.loopAudio = true
        original.cooldownSeconds = 3.5
        original.customFileName = "siren_alert.mp3"
        original.bookmarkData = "sample_bookmark_data".data(using: .utf8)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AudioConfig.self, from: data)
        
        XCTAssertEqual(decoded.volume, 0.75)
        XCTAssertEqual(decoded.loopAudio, true)
        XCTAssertEqual(decoded.cooldownSeconds, 3.5)
        XCTAssertEqual(decoded.customFileName, "siren_alert.mp3")
        XCTAssertEqual(decoded.bookmarkData, "sample_bookmark_data".data(using: .utf8))
    }
    
    func testSharedStoreAudioPersistence() {
        let store = SharedStore.shared
        
        var testConfig = AudioConfig()
        testConfig.volume = 0.42
        testConfig.loopAudio = false
        testConfig.cooldownSeconds = 4.0
        testConfig.customFileName = "test_custom.wav"
        
        store.saveAudioConfig(testConfig)
        let loaded = store.loadAudioConfig()
        
        XCTAssertEqual(loaded.volume, 0.42, accuracy: 0.001)
        XCTAssertEqual(loaded.loopAudio, false)
        XCTAssertEqual(loaded.cooldownSeconds, 4.0, accuracy: 0.001)
        XCTAssertEqual(loaded.customFileName, "test_custom.wav")
    }
}
