import XCTest
@testable import SiteSiren

final class DomainMatchingTests: XCTestCase {
    
    func testParentDomainMatchesExactAndSubdomains() {
        let rule = "youtube.com"
        
        // Exact matches
        XCTAssertTrue(DomainRule.matches(candidate: "youtube.com", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "www.youtube.com", ruleDomain: rule))
        
        // Subdomain matches
        XCTAssertTrue(DomainRule.matches(candidate: "music.youtube.com", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "m.youtube.com", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "accounts.youtube.com", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "sub.deep.music.youtube.com", ruleDomain: rule))
    }
    
    func testParentDomainDoesNotMatchUnrelatedOrParentSuffix() {
        let rule = "youtube.com"
        
        // Must NOT match domains containing the string as part of another label
        XCTAssertFalse(DomainRule.matches(candidate: "notyoutube.com", ruleDomain: rule))
        XCTAssertFalse(DomainRule.matches(candidate: "youtube-example.com", ruleDomain: rule))
        XCTAssertFalse(DomainRule.matches(candidate: "myoutube.com", ruleDomain: rule))
        XCTAssertFalse(DomainRule.matches(candidate: "the-youtube.com", ruleDomain: rule))
        
        // Must NOT match if rule is a prefix/subdomain of an external domain
        XCTAssertFalse(DomainRule.matches(candidate: "youtube.com.example.com", ruleDomain: rule))
        XCTAssertFalse(DomainRule.matches(candidate: "youtube.com.attacker.org", ruleDomain: rule))
    }
    
    func testCandidateWithProtocolsAndPaths() {
        let rule = "reddit.com"
        XCTAssertTrue(DomainRule.matches(candidate: "https://www.reddit.com/r/apple", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "http://old.reddit.com/", ruleDomain: rule))
        XCTAssertFalse(DomainRule.matches(candidate: "https://notreddit.com", ruleDomain: rule))
    }
    
    func testCaseInsensitiveMatching() {
        let rule = "Twitter.com"
        XCTAssertTrue(DomainRule.matches(candidate: "TWITTER.COM", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "api.twitter.com", ruleDomain: rule))
        XCTAssertTrue(DomainRule.matches(candidate: "API.TWITTER.COM", ruleDomain: rule))
    }
}
