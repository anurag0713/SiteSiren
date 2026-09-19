import XCTest
@testable import SiteSiren

final class SettingsPersistenceTests: XCTestCase {
    
    func testBlockedDomainsPersistence() {
        let store = SharedStore.shared
        
        let initialRules = [
            DomainRule(domain: "youtube.com"),
            DomainRule(domain: "reddit.com"),
            DomainRule(domain: "x.com")
        ]
        
        store.saveBlockedDomains(initialRules)
        let loaded = store.loadBlockedDomains()
        
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map { $0.domain }.sorted(), ["reddit.com", "x.com", "youtube.com"])
    }
    
    func testProtectionEnabledTogglePersistence() {
        let store = SharedStore.shared
        
        store.setProtectionEnabled(false)
        XCTAssertFalse(store.isProtectionEnabled())
        
        store.setProtectionEnabled(true)
        XCTAssertTrue(store.isProtectionEnabled())
    }
    
    func testBlockEventHistoryCappedAtLimit() {
        let store = SharedStore.shared
        store.clearBlockEvents()
        
        // Insert 120 events
        for i in 1...120 {
            let event = BlockEvent(domain: "test\(i).com", timestamp: Date(), processName: "Browser")
            store.recordBlockEvent(event)
        }
        
        let loadedEvents = store.loadBlockEvents()
        // Must be capped at AppConstants.maxActivityHistoryCount (100)
        XCTAssertEqual(loadedEvents.count, AppConstants.maxActivityHistoryCount)
        // Most recent event should be first
        XCTAssertEqual(loadedEvents.first?.domain, "test120.com")
        
        store.clearBlockEvents()
        XCTAssertTrue(store.loadBlockEvents().isEmpty)
    }
}
