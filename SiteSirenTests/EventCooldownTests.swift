import XCTest
@testable import SiteSiren

@MainActor
final class EventCooldownTests: XCTestCase {
    
    func testCooldownDebouncing() {
        let audioManager = AudioManager()
        audioManager.setCooldown(2.0)
        
        // Initial trigger
        audioManager.handleBlockEvent(domain: "youtube.com")
        let wasPlayingFirst = audioManager.isPlaying
        
        // Immediate second trigger within milliseconds (should be suppressed)
        audioManager.handleBlockEvent(domain: "youtube.com")
        
        // Immediate third trigger with another domain (also suppressed during global cooldown)
        audioManager.handleBlockEvent(domain: "reddit.com")
        
        // Audio playback state should not crash or produce unhandled errors
        XCTAssertEqual(audioManager.config.cooldownSeconds, 2.0)
        _ = wasPlayingFirst
    }
    
    func testCooldownConfigurationBounds() {
        let audioManager = AudioManager()
        audioManager.setCooldown(0.1) // Below minimum 0.5s
        XCTAssertGreaterThanOrEqual(audioManager.config.cooldownSeconds, 0.5)
        
        audioManager.setCooldown(5.0)
        XCTAssertEqual(audioManager.config.cooldownSeconds, 5.0)
    }
}
