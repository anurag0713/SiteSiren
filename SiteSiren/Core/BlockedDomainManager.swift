import Foundation
import Combine
import os.log

public enum DomainError: LocalizedError, Equatable {
    case invalidFormat
    case duplicateDomain(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Please enter a valid domain name (e.g. youtube.com)."
        case .duplicateDomain(let domain):
            return "'\(domain)' is already in your blocked list."
        }
    }
}

@MainActor
public final class BlockedDomainManager: ObservableObject {
    @Published public private(set) var blockedDomains: [DomainRule] = []
    @Published public var searchText: String = ""
    @Published public var errorMessage: String? = nil
    
    public var onRulesUpdated: (() -> Void)?
    
    private let logger = Logger(subsystem: AppConstants.appBundleIdentifier, category: "BlockedDomainManager")
    
    public init() {
        loadRules()
    }
    
    public var filteredDomains: [DomainRule] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return blockedDomains
        }
        return blockedDomains.filter { $0.domain.localizedCaseInsensitiveContains(trimmed) }
    }
    
    public func loadRules() {
        self.blockedDomains = SharedStore.shared.loadBlockedDomains()
    }
    
    @discardableResult
    public func addDomain(_ rawInput: String) -> Result<DomainRule, DomainError> {
        guard let normalized = DomainRule.normalize(rawInput) else {
            errorMessage = DomainError.invalidFormat.errorDescription
            return .failure(.invalidFormat)
        }
        
        // Prevent duplicate entries
        if blockedDomains.contains(where: { $0.domain.lowercased() == normalized.lowercased() }) {
            let error = DomainError.duplicateDomain(normalized)
            errorMessage = error.errorDescription
            return .failure(error)
        }
        
        let newRule = DomainRule(domain: normalized)
        blockedDomains.append(newRule)
        saveAndSync()
        errorMessage = nil
        logger.info("Added blocked domain: \(normalized)")
        return .success(newRule)
    }
    
    public func removeDomain(withId id: UUID) {
        if let index = blockedDomains.firstIndex(where: { $0.id == id }) {
            let removed = blockedDomains.remove(at: index)
            saveAndSync()
            logger.info("Removed blocked domain: \(removed.domain)")
        }
    }
    
    public func removeDomain(_ rule: DomainRule) {
        removeDomain(withId: rule.id)
    }
    
    private func saveAndSync() {
        SharedStore.shared.saveBlockedDomains(blockedDomains)
        SharedStore.postRulesUpdated()
        onRulesUpdated?()
    }
    
    // MARK: - Export & Import
    
    public func exportAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(blockedDomains),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    public func exportAsText() -> String {
        blockedDomains.map { $0.domain }.joined(separator: "\n")
    }
    
    public func importFromText(_ content: String) -> (added: Int, skipped: Int) {
        let lines = content.components(separatedBy: .newlines)
        var added = 0
        var skipped = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if case .success = addDomain(trimmed) {
                added += 1
            } else {
                skipped += 1
            }
        }
        return (added, skipped)
    }
    
    public func importFromJSON(_ jsonString: String) -> (added: Int, skipped: Int) {
        guard let data = jsonString.data(using: .utf8),
              let rules = try? JSONDecoder().decode([DomainRule].self, from: data) else {
            return (0, 0)
        }
        var added = 0
        var skipped = 0
        for rule in rules {
            if case .success = addDomain(rule.domain) {
                added += 1
            } else {
                skipped += 1
            }
        }
        return (added, skipped)
    }
}
