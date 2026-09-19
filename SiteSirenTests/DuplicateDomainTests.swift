import XCTest
@testable import SiteSiren

@MainActor
final class DuplicateDomainTests: XCTestCase {
    
    func testAddDuplicateDomainFails() {
        let manager = BlockedDomainManager()
        // Clear any preexisting rules for testing
        for rule in manager.blockedDomains {
            manager.removeDomain(rule)
        }
        
        let result1 = manager.addDomain("youtube.com")
        XCTAssertTrue(result1.isSuccess)
        
        // Adding the exact same domain
        let result2 = manager.addDomain("youtube.com")
        XCTAssertFalse(result2.isSuccess)
        
        // Adding with uppercase and www. prefix (should normalize to youtube.com and fail as duplicate)
        let result3 = manager.addDomain("WWW.YOUTUBE.COM")
        XCTAssertFalse(result3.isSuccess)
        
        // Adding with https scheme and trailing slash
        let result4 = manager.addDomain("https://youtube.com/")
        XCTAssertFalse(result4.isSuccess)
        
        // Total count should remain 1
        XCTAssertEqual(manager.blockedDomains.count, 1)
        
        // Adding a different domain succeeds
        let result5 = manager.addDomain("reddit.com")
        XCTAssertTrue(result5.isSuccess)
        XCTAssertEqual(manager.blockedDomains.count, 2)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
