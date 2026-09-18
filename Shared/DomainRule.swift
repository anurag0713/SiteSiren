import Foundation

public struct DomainRule: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let domain: String
    public let createdAt: Date
    
    public init(id: UUID = UUID(), domain: String, createdAt: Date = Date()) {
        self.id = id
        self.domain = domain
        self.createdAt = createdAt
    }
    
    /// Normalizes a user-entered string or URL into a clean, canonical domain.
    ///
    /// Examples:
    /// - "https://www.youtube.com/watch?v=123" -> "youtube.com"
    /// - "www.reddit.com/" -> "reddit.com"
    /// - "http://m.youtube.com" -> "m.youtube.com"
    /// - "YOUTUBE.COM" -> "youtube.com"
    /// - "accounts.google.com:443" -> "accounts.google.com"
    public static func normalize(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        
        // If a scheme is already present, or if we should treat it as a URL
        let urlCandidate = text.contains("://") ? text : "https://" + text
        if let url = URL(string: urlCandidate), let host = url.host {
            text = host
        } else {
            // Fallback: strip any path component
            if let slashIndex = text.firstIndex(of: "/") {
                text = String(text[..<slashIndex])
            }
        }
        
        // Strip port if present (e.g. "example.com:8080")
        if let colonIndex = text.firstIndex(of: ":") {
            text = String(text[..<colonIndex])
        }
        
        // Strip trailing dots (e.g. FQDN "youtube.com.")
        while text.hasSuffix(".") {
            text.removeLast()
        }
        
        // Strip leading www.
        if text.hasPrefix("www.") {
            text = String(text.dropFirst(4))
        }
        
        // Validate host: must have at least one dot, no spaces, no invalid characters
        guard text.contains("."),
              !text.contains(" "),
              !text.hasPrefix("."),
              !text.hasSuffix("."),
              text.count >= 3 else {
            return nil
        }
        
        return text
    }
    
    /// Checks if a candidate host matches the rule as the domain or any subdomain of the rule.
    ///
    /// Examples with rule "youtube.com":
    /// - "youtube.com" -> true
    /// - "www.youtube.com" -> true
    /// - "music.youtube.com" -> true
    /// - "notyoutube.com" -> false
    /// - "youtube-example.com" -> false
    /// - "youtube.com.example.com" -> false
    public static func matches(candidate: String, ruleDomain: String) -> Bool {
        guard let normalizedCandidate = normalize(candidate) else {
            let fallbackCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedRule = ruleDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return fallbackCandidate == normalizedRule || fallbackCandidate.hasSuffix("." + normalizedRule)
        }
        
        let normalizedRule = (normalize(ruleDomain) ?? ruleDomain).lowercased()
        
        if normalizedCandidate == normalizedRule {
            return true
        }
        
        if normalizedCandidate.hasSuffix("." + normalizedRule) {
            return true
        }
        
        return false
    }
}
