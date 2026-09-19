import XCTest
@testable import SiteSiren

final class DomainNormalizationTests: XCTestCase {
    
    func testYouTubeURLNormalization() {
        let input = "https://www.youtube.com/watch?v=123"
        let normalized = DomainRule.normalize(input)
        XCTAssertEqual(normalized, "youtube.com")
    }
    
    func testRedditTrailingSlashNormalization() {
        let input = "www.reddit.com/"
        let normalized = DomainRule.normalize(input)
        XCTAssertEqual(normalized, "reddit.com")
    }
    
    func testSchemeVariations() {
        XCTAssertEqual(DomainRule.normalize("http://example.com"), "example.com")
        XCTAssertEqual(DomainRule.normalize("https://example.com"), "example.com")
        XCTAssertEqual(DomainRule.normalize("ftp://example.com"), "example.com")
    }
    
    func testSubdomainsPreserved() {
        XCTAssertEqual(DomainRule.normalize("m.youtube.com"), "m.youtube.com")
        XCTAssertEqual(DomainRule.normalize("music.youtube.com/explore"), "music.youtube.com")
        XCTAssertEqual(DomainRule.normalize("accounts.google.com/signin"), "accounts.google.com")
    }
    
    func testCaseInsensitivityAndWhitespace() {
        XCTAssertEqual(DomainRule.normalize("   WWW.YOUTUBE.COM/feed/explore  \n"), "youtube.com")
    }
    
    func testPortsAndTrailingDots() {
        XCTAssertEqual(DomainRule.normalize("youtube.com:443/"), "youtube.com")
        XCTAssertEqual(DomainRule.normalize("youtube.com."), "youtube.com")
        XCTAssertEqual(DomainRule.normalize("www.reddit.com.:8080/r/swift"), "reddit.com")
    }
    
    func testInvalidDomains() {
        XCTAssertNil(DomainRule.normalize(""))
        XCTAssertNil(DomainRule.normalize("   "))
        XCTAssertNil(DomainRule.normalize("notadomain"))
        XCTAssertNil(DomainRule.normalize("invalid domain with spaces.com"))
        XCTAssertNil(DomainRule.normalize(".com"))
        XCTAssertNil(DomainRule.normalize("."))
    }
}
